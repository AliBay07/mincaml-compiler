type reg_expr =
  | Int of int 
  | Neg of string
  | Add of string * reg_expr
  | Sub of string * reg_expr
  | Call of string
  | If of string * (string * reg_expr) * regt list * regt list
  | Reg of string
  | Unit

and regt = 
  | Let of string * reg_expr 
  | Exp of reg_expr
  | Store of reg_expr * string 
  | Load of string * reg_expr 

and letregdef = 
  | Fun of reg_function

and reg_function = {
  name : string;
  body : regt list;
}

let if_label_counter = ref 0

let generate_if_label () =
  let label = "l" ^ string_of_int !if_label_counter in
  if_label_counter := !if_label_counter + 1;
  label

let rec count_lets_in_regt : regt -> int = function
  | Let (_, _) -> 1
  | Exp _ | Store (_, _) | Load (_, _) -> 0

let rec count_lets_in_reg_function : reg_function -> int =
  fun { body; _ } -> List.fold_left (fun acc stmt -> acc + count_lets_in_regt stmt) 0 body

  and generate_asm_regt : regt -> string list = function
  | Let (s, expr) ->
    (match expr with
     | Int n -> [Printf.sprintf "mov %s, #%d" s n]
     | Reg reg -> [Printf.sprintf "mov %s, %s" s reg]
     | Add (s1, expr) ->
       (match expr with
        | Int n -> [Printf.sprintf "add %s, %s, #%d" s s1 n]
        | Reg reg -> [Printf.sprintf "add %s, %s, %s" s s1 reg]
        | _ -> ["Error"])
     | Sub (s1, expr) ->
       (match expr with
        | Int n -> [Printf.sprintf "sub %s, %s, #%d" s s1 n]
        | Reg reg -> [Printf.sprintf "sub %s, %s, %s" s s1 reg]
        | _ -> ["Error"])
     | Call (func_name) -> [Printf.sprintf "bl %s" func_name; Printf.sprintf "mov %s, r0" s]
     | _ -> ["Error"])
  | Exp exp ->
  (match exp with
    | If (cmp_type, (r1, Reg r2), true_branch, false_branch) ->
      let true_label = generate_if_label () in
      let end_label = generate_if_label () in
      Printf.sprintf "cmp %s, %s" r1 r2 ::
      Printf.sprintf "b%s %s" cmp_type true_label ::
      List.concat (List.map generate_asm_regt false_branch) @
      Printf.sprintf "b %s" end_label ::
      Printf.sprintf "%s:" true_label ::
      List.concat (List.map generate_asm_regt true_branch) @
      Printf.sprintf "%s:" end_label :: []
    | Int n -> [Printf.sprintf "mov r0, #%d" n]
    | Reg reg -> [Printf.sprintf "mov r0, %s" reg]
    | Unit -> []
    | _ -> ["Error"])
  | Store (Reg reg, mem) -> [Printf.sprintf "str %s, %s" reg mem]
  | Load (s, Reg reg) -> [Printf.sprintf "ldr %s, %s" reg s]
  | _ -> ["Not Found"]

and generate_asm_fun_internal : reg_function -> string list = fun { name; body } ->
  let size = count_lets_in_reg_function { name; body } in
  [Printf.sprintf "%s:" name] @ generate_prologue size @ List.concat (List.map generate_asm_regt body) @ generate_epilogue

and generate_prologue size =
  ["add sp, sp, #-4"; "str fp, [sp]"; "add fp, sp, #0"; "add sp, sp, #-" ^ string_of_int (size * 4)]

and generate_epilogue =
  ["add sp, fp, #0"; "ldr fp, [sp]"; "add sp, sp, #4"; "bx lr"]

let generate_asm_reg (defs: letregdef list) : string list =
  match defs with
  | [] -> []
  | _ ->
    let rec generate_asm_internal acc = function
      | [] -> acc
      | hd :: tl ->
        let asm_hd = match hd with Fun f -> generate_asm_fun_internal f in
        generate_asm_internal (acc @ asm_hd) tl
    in
    generate_asm_internal [] defs

let () =
  let result_asm_reg =
    generate_asm_reg
      [
        Fun
        { name = "_";
          body =
            [
              Let ("r4", Int 1); Store (Reg "r4", "[fp - 4]"); Let ("r5", Call("_f"));
              Store (Reg "r5", "[fp - 8]");
              Exp(If("le", ("r4", Reg "r5"), [Let("r6", Int 1)], [Let("r6", Int 2)]));
              Let ("r6", Sub ("r5", Reg "r4"));
              Store (Reg "r6", "[fp - 16]"); Let ("r6", Add ("r5", Reg "r4"));
              Store (Reg "r5", "[fp - 4]");
              Exp (Int 2)
            ]
          };
          Fun 
          { name = "_f";
          body =
            [Let ("r4", Reg "r0"); Store (Reg "r4", "[fp - 4]");
            Exp (Int 5)
            ]
          };
        ]
  in
  let output_file_reg = "output.asm" in
  let oc_reg = open_out output_file_reg in
  List.iter (fun instruction -> output_string oc_reg (instruction ^ "\n")) result_asm_reg;
  close_out oc_reg;
  print_endline ("Results written to " ^ output_file_reg)
