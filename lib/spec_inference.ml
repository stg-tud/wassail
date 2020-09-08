open Core_kernel
open Helpers

module State = struct
  (** The state is a specification of the runtime components *)
  type state = {
    vstack : Var.t list;
    locals : Var.t list;
    globals : Var.t list;
    memory : Var.t Var.Map.t;
  }
  [@@deriving compare, equal]

  (** Returns all variables contained in the memory of a state *)
  let memvars (s : state) : Var.t list =
    (List.concat (List.map (Var.Map.to_alist s.memory)
                    ~f:(fun (k, v) -> [k; v])))

  (** Returns all the variables contained in the state *)
  let vars_of (s : state) : Var.Set.t =
    Var.Set.union (Var.Set.of_list s.vstack)
      (Var.Set.union (Var.Set.of_list s.locals)
         (Var.Set.union (Var.Set.of_list s.globals)
            (Var.Set.of_list (memvars s))))

  (** Returns all the variables contained in the spec map *)
  let vars (data : (state * state) IntMap.t) : Var.Set.t =
    List.fold_left (IntMap.to_alist data)
      ~init:Var.Set.empty
      ~f:(fun acc (_, (pre, post)) ->
          Var.Set.union acc (Var.Set.union (vars_of pre) (vars_of post)))

  let extract_different_vars (s1 : state) (s2 : state) : (Var.t * Var.t) list =
    let f (l1 : Var.t list) (l2 : Var.t list) : (Var.t * Var.t) list =
      assert (List.length l1 = List.length l2);
      List.filter_map (List.map2_exn l1 l2 ~f:(fun v1 v2 -> (v1, v2, Var.equal v1 v2)))
        ~f:(fun (v1, v2, eq) -> if not eq then Some (v1, v2) else None) in
    let fvstack (l1 : Var.t list) (l2 : Var.t list) : (Var.t * Var.t) list =
      (* Like f, but only checks a prefix.
         For example, it can sometimes happen that on one path we have [x, y] as the vstack, and another we have [y].
         We can safely assume that if the code has passed validation, then y will never be used.
         Hence, it is safe to treat the first vstack as if it was [x] *)
      let min_size = min (List.length l1) (List.length l2) in
      f (List.take l1 min_size) (List.take l2 min_size) in
    let fmap (m1 : Var.t Var.Map.t) (m2 : Var.t Var.Map.t) : (Var.t * Var.t) list =
      assert (Stdlib.(=) (Var.Map.keys m1) (Var.Map.keys m2)); (* Memory keys never change (assumption) *)
      List.filter_map (Var.Map.keys m1) ~f:(fun k ->
          let v1 = Var.Map.find_exn m1 k in
          let v2 = Var.Map.find_exn m2 k in
          if Var.equal v1 v2 then None else Some (v1, v2)) in
    (fvstack s1.vstack s2.vstack) @ (f s1.locals s2.locals) @ (f s1.globals s2.globals) @ (fmap s1.memory s2.memory)

  let ret (i : state Instr.t) : Var.t =
    List.hd_exn (Instr.annotation_after i).vstack
end

module Spec_inference (* : Transfer.TRANSFER TODO *) = struct
  include State

  (*---- Types ----*)
  (** Spec inference does not require any annotation *)
  type annot_expected = unit

  (** No summaries for this analysis *)
  type summary = unit
  let summary _ _ = ()
  let init_summaries _ = ()

  (*---- Helper functions ----*)
  (** Like List.drop, but raises an exception if the list does not contain enough element *)
  let drop (n : int) (vstack : Var.t list) =
    assert (List.length vstack >= n);
    List.drop vstack n

  let get (n : int) (l : Var.t list) = List.nth_exn l n

  let set (n : int) (l : Var.t list) (v : Var.t) = List.mapi l ~f:(fun i v' -> if i = n then v else v')

  (*---- State ----*)

  let init_state (cfg : 'a Cfg.t) : state = {
    vstack = []; (* the vstack is initially empty *)
    locals = List.mapi (cfg.arg_types @ cfg.local_types) ~f:(fun i _ -> Var.Local i);
    globals = List.mapi cfg.global_types ~f:(fun i _ -> Var.Global i);
    memory = begin
      let key (label : Instr.label) (n : int) : Var.t = MemoryKey (label, n) in
      let value (label : Instr.label) (n : int) : Var.t = MemoryVal (label, n) in
      List.fold_left (IntMap.data cfg.basic_blocks)
        ~init:Var.Map.empty
        ~f:(fun m block -> match block.content with
            | Data instrs ->
              List.fold_left instrs
                ~init:m
                ~f:(fun m i -> match i.instr with
                    | Load _op | Store _op ->
                      Var.Map.add_exn ~key:(key i.label 0) ~data:(value i.label 0) m
                    | _ -> m)
            | Control _ | ControlMerge -> m)
    end;
  }

  let bottom : state = {
    vstack = [];
    locals = [];
    globals = [];
    memory = Var.Map.empty;
  }

  let bottom_state _ = bottom

  let state_to_dot_string (s : state) : string =
    Printf.sprintf "[%s], [%s]"
      (String.concat ~sep:", " (List.map s.vstack ~f:Var.to_string))
      (String.concat ~sep:", " (List.map s.locals ~f:Var.to_string))

  let state_to_string (s : state) : string =
    Printf.sprintf "{\nvstack: [%s]\nlocals: [%s]\nglobals: [%s]\nmemory: [%s]\n}"
      (String.concat ~sep:", " (List.map s.vstack ~f:Var.to_string))
      (String.concat ~sep:", " (List.map s.locals ~f:Var.to_string))
      (String.concat ~sep:", " (List.map s.globals ~f:Var.to_string))
      (String.concat ~sep:", " (List.map (Var.Map.to_alist s.memory) ~f:(fun (k, v) -> Printf.sprintf "%s: %s" (Var.to_string k) (Var.to_string v))))

  let join_state (_s1 : state) (s2 : state) : state =
    s2 (* only keep the "most recent" state, this is safe for this analysis *)

  (* No widening *)
  let widen_state _ s2 = s2

  (*---- Transfer functions ----*)

  let data_instr_transfer
      (_module_ : Wasm_module.t)
      (_cfg : annot_expected Cfg.t)
      (i : annot_expected Instr.labelled_data)
      (state : state)
    : state =
    let key (n : int) : Var.t = MemoryKey (i.label, n) in
    let value (n : int) : Var.t = MemoryValNew (i.label, n) in
    let ret = Var.Var i.label in
    match i.instr with
    | Nop -> state
    | MemorySize -> { state with vstack = ret :: state.vstack }
    | MemoryGrow -> { state with vstack = ret :: drop 1 state.vstack }
    | Drop -> { state with vstack = drop 1 state.vstack }
    | Select -> { state with vstack = ret :: (drop 3 state.vstack) }
    | LocalGet l -> { state with vstack = get l state.locals :: state.vstack }
    | LocalSet l -> { state with vstack = drop 1 state.vstack; locals = set l state.locals (List.hd_exn state.vstack) }
    | LocalTee l -> { state with locals = set l state.locals (List.hd_exn state.vstack) }
    | GlobalGet g -> { state with vstack = get g state.globals :: state.vstack }
    | GlobalSet g -> { state with globals = set g state.globals (List.hd_exn state.vstack) }
    | Const _ -> { state with vstack = ret :: state.vstack }
    | Compare _ -> { state with vstack = ret :: (drop 2 state.vstack) }
    | Binary _ -> { state with vstack = ret :: (drop 2 state.vstack) }
    | Unary _ -> { state with vstack = ret :: (drop 1 state.vstack) }
    | Test _ -> { state with vstack = ret :: (drop 1 state.vstack) }
    | Convert _ -> { state with vstack = ret :: (drop 1 state.vstack) }
    | Load _ ->
      (* We look up the value at the address *)
      (* TODO: load can load one byte, or more. For now, this is entirely encoded in the constraints *)
      (* let v = Var.Map.find_exn state.memory (key 0) in *)
      { state with vstack = ret :: (drop 1 state.vstack) }
    | Store _ ->
      { state with vstack = drop 2 state.vstack;
                   memory = Var.Map.update state.memory (key 0) ~f:(fun _ -> (value 0)) }

  let control_instr_transfer (_module_ : Wasm_module.t) (cfg : 'a Cfg.t) (i : ('a Instr.control, 'a) Instr.labelled) (state : state) : [`Simple of state | `Branch of state * state] =
    let ret = Var.Var i.label in
    match i.instr with
    | Call ((arity_in, arity_out), _) ->
      `Simple { state with vstack = (if arity_out = 1 then [ret] else []) @ (drop arity_in state.vstack) }
    | CallIndirect ((arity_in, arity_out), _) ->
      (* Like call, but reads the function index from the vstack *)
      `Simple { state with vstack = (if arity_out = 1 then [ret] else []) @ (drop (arity_in+1) state.vstack) }
    | Br _ -> `Simple state
    | BrIf _ | If _ ->
      `Branch ({ state with vstack = drop 1 state.vstack },
               { state with vstack = drop 1 state.vstack })
    | BrTable _ -> `Simple { state with vstack = drop 1 state.vstack }
    | Return -> `Simple (if List.length cfg.return_types = 1 then
                           { state with vstack = [List.hd_exn state.vstack] }
                         else
                           { state with vstack = [] })
    | Unreachable -> `Simple { state with vstack = [] }
    | _ -> failwith (Printf.sprintf "Unsupported control instruction: %s" (Instr.control_to_short_string i.instr))

  let merge
      (_module_ : Wasm_module.t)
      (cfg : annot_expected Cfg.t)
      (block : annot_expected Basic_block.t)
      (states : state list) : state =
    let counter = ref 0 in
    let new_var () : Var.t =
      let res = Var.Merge (block.idx, !counter) in
      counter := !counter + 1;
      res in
    let _ : Var.t = new_var() in
    match block.content with
    | ControlMerge ->
      (* Multiple cases: either we have no predecessor, we have unanalyzed predecessors, or we have only analyzed predecessors *)
      begin match states with
        | [] ->
          (* entry node *)
          init_state cfg
        | s :: [] ->
          (* single predecessor node?! *)
          s
        | _ ->
          (* multiple predecessors *)
          let bot = bottom_state cfg in
          begin match List.filter states ~f:(fun s -> not (equal_state s bot)) with
            | [] -> failwith "No predecessor of a merge node have been analyzed, should not happen"
            | s :: [] -> (* only one non-bottom predecessor *) s
            | states ->
              (*Printf.printf "merge block %s, states: %s\n" (Basic_block.to_string block (fun _ -> "")) (String.concat ~sep:"," (List.map states ~f:state_to_string)); *)
              (* multiple predecessors to merge *)
              (* First compute the state with holes where we will need to put merge variables *)
              let with_holes = List.fold_left states
                  ~init:(List.hd_exn states)
                  ~f:(fun acc s ->
                      let f opt v = match opt with
                        | v' when Var.equal v v' -> v'
                        | _ -> (* Printf.printf "hole created for %s, %s\n" (Var.to_string opt) (Var.to_string v); *) Var.Hole (* this is a hole *)
                      in
                      { vstack = List.map2_exn acc.vstack s.vstack ~f:f;
                        locals = List.map2_exn acc.locals s.locals ~f:f;
                        globals = List.map2_exn acc.globals s.globals ~f:f;
                        memory = (* Var.Map.map2_exn *) acc.memory (* s.memory ~f:f *) }) in (* TODO: deal with memory *)
              (* Then, add merge variables *)
              let plug_holes = (function
                  | Var.Hole -> (* add a merge variable *) new_var ()
                  | v -> (* no hole, keep the variable *) v) in
              { vstack = List.map with_holes.vstack ~f:plug_holes;
                locals = List.map with_holes.locals ~f:plug_holes;
                globals = List.map with_holes.globals ~f:plug_holes;
                memory = Var.Map.map with_holes.memory ~f:plug_holes }
          end
      end
    | _ ->
      (* not a control-flow merge, should only be one predecessor (or none if it is the entry point) *)
      begin match states with
        | [] -> init_state cfg
        | s :: [] -> s
        | _ ->  failwith (Printf.sprintf "Invalid block with multiple input states: %d" block.idx)
      end

  let merge_flows
      (module_ : Wasm_module.t)
      (cfg : annot_expected Cfg.t)
      (block : annot_expected Basic_block.t)
      (states : (int * state) list)
    : state =
    (* Checks the validity of the merge and dispatches to `merge` *)
    begin match states with
      | _ :: _ :: _ -> begin match block.content with
          | ControlMerge -> ()
          | _ -> failwith (Printf.sprintf "Invalid block with multiple input states: %d" block.idx)
        end
      | _ -> ()
    end;
    merge module_ cfg block (List.map ~f:snd states)

end

include Spec_inference
include State
    
