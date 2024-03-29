open Printf

type t = 
  | Unit
  | Bool of bool
  | Int of int
  | Float of float
  | Not of t
  | Neg of t
  | Add of t * t
  | Sub of t * t
  | FNeg of t
  | FAdd of t * t
  | FSub of t * t
  | FMul of t * t
  | FDiv of t * t
  | Eq of t * t
  | LE of t * t
  | If of t * t * t
  | Let of (Id.t * Type.t) * t * t
  | Var of Id.t
  | LetRec of fundef * t
  | App of t * t list
  | Tuple of t list
  | LetTuple of (Id.t * Type.t) list * t * t
  | Array of t * t
  | Get of t * t
  | Put of t * t * t
and fundef = { name : Id.t * Type.t; args : (Id.t * Type.t) list; body : t }



(*************************************************************************
 * functions to convert ast to string with or without type annotation
 *)
let rec infix_to_string (to_s : 'a -> string) (l : 'a list) (op : string) : string = 
  match l with 
  | [] -> ""
  | [x] -> to_s x
  | hd :: tl -> (to_s hd) ^ op ^ (infix_to_string to_s tl op)
      
      
let rec to_string_rec (show_type:bool) (exp:t) : string =
  let to_string = to_string_rec show_type in
    match exp with
    | Unit -> "()"
    | Bool b -> if b then "true" else "false"
    | Int i -> string_of_int i
    | Float f -> sprintf "%.2f" f
    | Not e -> sprintf "(not %s)" (to_string e)
    | Neg e -> sprintf "(- %s)" (to_string e)
    | Add (e1, e2) -> sprintf "(%s + %s)" (to_string e1) (to_string e2)
    | Sub (e1, e2) -> sprintf "(%s - %s)" (to_string e1) (to_string e2) 
    | FNeg e -> sprintf "(-. %s)" (to_string e)
    | FAdd (e1, e2) -> sprintf "(%s +. %s)" (to_string e1) (to_string e2)
    | FSub (e1, e2) -> sprintf "(%s -. %s)" (to_string e1) (to_string e2) 
    | FMul (e1, e2) -> sprintf "(%s *. %s)" (to_string e1) (to_string e2)
    | FDiv (e1, e2) -> sprintf "(%s /. %s)" (to_string e1) (to_string e2) 
    | Eq (e1, e2) -> sprintf "(%s = %s)" (to_string e1) (to_string e2) 
    | LE (e1, e2) -> sprintf "(%s <= %s)" (to_string e1) (to_string e2)  
    | If (e1, e2, e3) -> 
      sprintf "(if %s then %s else %s)" (to_string e1) (to_string e2) (to_string e3)   
    | Let ((id,t), e1, e2) -> 
      sprintf "(let %s%s = %s in %s)"
        (Id.to_string id)
        (if show_type then ":" ^ (Type.to_string2 t) else "")
        (to_string e1)
        (to_string e2)   
    | Var id -> Id.to_string id
    | App (e1, le2) -> sprintf "(%s %s)" (to_string e1) (infix_to_string to_string le2 " ") 
    | LetRec (fd, e) ->  
      sprintf "(let rec %s %s%s = %s in %s)" 
        (let (x, _) = fd.name in (Id.to_string x))
        (infix_to_string (fun (x,_) -> (Id.to_string x)) fd.args " ")
        (if show_type then ":" ^ (let (_, y) = fd.name in (Type.to_string2 y)) else "")
        (to_string fd.body)
        (to_string e)
    | LetTuple (l, e1, e2)-> 
      sprintf "(let (%s)%s = %s in %s)" 
        (infix_to_string (fun (x, _) -> Id.to_string x) l ", ")
        (if show_type then ":tuple(" ^ (infix_to_string (fun (_, y) -> Type.to_string2 y) l " ") ^ ")" else "")
        (to_string e1)
        (to_string e2)
    | Get(e1, e2) -> sprintf "%s.(%s)" (to_string e1) (to_string e2)
    | Put(e1, e2, e3) -> sprintf "(%s.(%s) <- %s)"  (to_string e1) (to_string e2) (to_string e3)
    | Tuple(l) -> sprintf "(%s)" (infix_to_string to_string l ", ")
    | Array(e1,e2) -> sprintf "(Array.create %s %s)" (to_string e1) (to_string e2)

let to_string = to_string_rec false
let to_string_with_types = to_string_rec true





let rec clone_ast ast =
  let rec clone_list l = List.map clone_ast l in
    match ast with
    | Unit -> ast
    | Bool b -> Bool(b)
    | Int i -> Int(i)
    | Float f -> Float(f)
    | Not e -> Not(clone_ast e)
    | Neg e -> Neg(clone_ast e)
    | Add (e1, e2) -> Add(clone_ast e1, clone_ast e2)
    | Sub (e1, e2) -> Sub(clone_ast e1, clone_ast e2)
    | FNeg e -> FNeg(clone_ast e)
    | FAdd (e1, e2) -> FAdd(clone_ast e1, clone_ast e2)
    | FSub (e1, e2) -> FSub(clone_ast e1, clone_ast e2)
    | FMul (e1, e2) -> FMul(clone_ast e1, clone_ast e2)
    | FDiv (e1, e2) -> FDiv(clone_ast e1, clone_ast e2)
    | Eq (e1, e2) -> Eq(clone_ast e1, clone_ast e2) 
    | LE (e1, e2) -> LE(clone_ast e1, clone_ast e2)
    | If (e1, e2, e3) -> If(clone_ast e1, clone_ast e2, clone_ast e3)
    | Let ((id,t), e1, e2) -> Let((id, t), clone_ast e1, clone_ast e2)
    | Var id -> Var(id)
    | App (e1, le2) -> App(clone_ast e1, clone_list le2)
    | LetRec (fd, e) -> LetRec({ name = fd.name; args = fd.args; body = clone_ast fd.body}, clone_ast e)
    | LetTuple (l, e1, e2)-> LetTuple(l, clone_ast e1, clone_ast e2)
    | Get(e1, e2) -> Get(clone_ast e1, clone_ast e2)
    | Put(e1, e2, e3) -> Put(clone_ast e1, clone_ast e2, clone_ast e3)
    | Tuple(l) -> Tuple(clone_list l)
    | Array(e1,e2) -> Array(clone_ast e1, clone_ast e2)