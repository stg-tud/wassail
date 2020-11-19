open Helpers

type edge = (int * bool option) list (* TODO: change this to a set? *)
type 'a t = {
  (* Is this function exported or not? *)
  exported: bool;
  (* The name of the function *)
  name: string;
  (* The index of this CFG *)
  idx: int;
  (* Types of globals (they are not specific to this CFG, but useful to have here) *)
  global_types: Type.t list;
  (* Types of arguments *)
  arg_types: Type.t list;
  (* Types of locals *)
  local_types: Type.t list;
  (* Types of return values *)
  return_types: Type.t list;
  (* All basic blocks contained in this CFG, indexed in a map by their index *)
  basic_blocks: 'a Basic_block.t IntMap.t;
  (* All instructions contained in this CFG, indexed in a map by their label *)
  instructions : 'a Instr.t IntMap.t;
  (* The edges between basic blocks (forward direction) *)
  edges: edge IntMap.t;
  (* The edges between basic blocks (backward direction) *)
  back_edges: edge IntMap.t;
  (* The entry block *)
  entry_block: int;
  (* The exit block *)
  exit_block: int;
  (* The loop heads *)
  loop_heads: IntSet.t;
}

(** Equality on CFGs *)
val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

(** Return the call dependencies of a CFG, i.e., the indices of the functions that are directly called within this CFG.
    This ignores indirect calls *)
(* val dependencies : 'a t -> int list *)

(** Return the string representation of a CFG *)
val to_string : 'a t -> string

(** Return the DOT graph representatino of a CFG *)
val to_dot : 'a t -> ('a -> string) -> string

(** Find a basic block given its index *)
val find_block_exn : 'a t -> int -> 'a Basic_block.t

(** Find an instruction given its label *)
val find_instr_exn : 'a t -> Instr.label -> 'a Instr.t

(** Extract the successors of a block in the CFG, given its index.
    Return the successors as a list of their indices *)
val successors : 'a t -> int -> int list

(** Extract the predecessors of a block in the CFG, given its index.
    Return the predecessors as a list of their indices *)
val predecessors : 'a t -> int -> (int * bool option) list

(** Find the functions called in this CFG *)
val callees : 'a t -> IntSet.t

(** Find the callers of this function *)
val callers : 'a t IntMap.t -> 'a t -> IntSet.t

(** Return all the instructions within this CFG *)
(* val all_block_indices : 'a t -> IntSet.t *)

(** Return all the instructions contained within this CFG (in no particular order) *)
val all_instructions : 'a t -> 'a Instr.t list

(** Return all merge blocks contained within this CFG (in no particular order) *)
val all_merge_blocks : 'a t -> 'a Basic_block.t list

(** Return all the indices of the blocks within this CFG *)
val all_block_indices : 'a t -> IntSet.t

(** Return the labels of all the instructions contained within this CFG *)
val all_instruction_labels : 'a t -> IntSet.t

(** Return all annotations used in this CFG *)
val all_annots : 'a t -> 'a list

(** Change the annotations of a CFG *)
val annotate : 'a t -> ('b * 'b) IntMap.t -> ('b * 'b) IntMap.t -> 'b t

(** Add more annotations to an already-annotated CFG *)
val add_annotation : 'a t -> ('b * 'b) IntMap.t -> ('b * 'b) IntMap.t -> ('a * 'b) t

(** Return the forward edges of a node, given its index *)
val forward_edges_from_node : 'a t -> int -> (int * bool option) list

(** Return the backward edges of a node, given its index *)
val backward_edges_from_node : 'a t -> int -> (int * bool option) list

