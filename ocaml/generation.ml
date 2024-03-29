open RegAlloc

(* Blocks which will contain the generate ARM assembly code *)
let header : string list ref = ref [".text"; ".global main"]
let consts : string list ref = ref [""]
let floats : string list ref = ref []

(* Label counters *)
let if_label_counter = ref 0
let num_label_counter = ref 0

(* A stack which will keep track of the current sp value in case we need to update the SP *)
let sp_values : int list ref = ref []

(* A Boolean which will be 1 if we have parameters pushed on the stack, else 0 *)
let pushed_vars : int ref = ref 0

(* Generates a label for an if block *)
let generate_if_label () =
  let label = "l" ^ string_of_int !if_label_counter in
  if_label_counter := !if_label_counter + 1;
  label

(* Generate a label for large constants *)
let generate_num_label () =
  let label = "const_" ^ string_of_int !num_label_counter in
  num_label_counter := !num_label_counter + 1;
  label

(* Function which will convert the ASML to ARM assembly *)
let rec generate_asm_regt : regt -> string list = function
| Let (s, expr) ->
  (match expr with
    | Int n ->
      if s.[0] = 'r' then
        begin
        if n <= 255 then
          [Printf.sprintf "\tmov %s, #%d" s n]
        else
          [Printf.sprintf "\tldr %s, =#%d" s n]
        end
      else
        begin
        if n <= 255 then
          [Printf.sprintf "\tvmov.f32 %s, #%d" s n]
        else
          [Printf.sprintf "\tvldr.f32 %s, =#%d" s n]
        end
    | Reg reg ->
      if s = reg then
        []
      else
        if s.[0] = 'r' && reg.[0] = 'r' then
          [Printf.sprintf "\tmov %s, %s" s reg]
        else
          begin
          if s <> "r0" then
            [Printf.sprintf "\tvmov.f32 %s, %s" s reg]
          else
            [Printf.sprintf "\tvmov.f32 s0, %s" reg]
          end
    | Add (s1, expr) ->
      (match expr with
      | Int n -> 
        if s = s1 && n = 0 then
          []
        else if n <= 255 then
          [Printf.sprintf "\tadd %s, %s, #%d" s s1 n]
        else
          [Printf.sprintf "\tldr r12, =#%d" n; Printf.sprintf "\tadd %s, %s, r12" s s1]
      | Reg reg -> 
        if s = s1 && s = reg then
          [Printf.sprintf "\tlsl %s, %s, #1" s s]
        else
          [Printf.sprintf "\tadd %s, %s, %s" s s1 reg]
      | _ -> assert false)
    | Fadd (s1, label) -> [Printf.sprintf "\tvadd.f32 %s, %s, %s" s s1 label]
    | Sub (s1, expr) ->
      (match expr with
      | Int n -> 
        if s = s1 && n = 0 then
          []
        else if n <= 255 then
          [Printf.sprintf "\tsub %s, %s, #%d" s s1 n]
        else
          [Printf.sprintf "\tldr r12, =#%d" n; Printf.sprintf "\tsub %s, %s, r12" s s1]
      | Reg reg -> 
        if s = s1 && s = reg then
          [Printf.sprintf "\tlsr %s, %s, #1" s s]
        else
          [Printf.sprintf "\tsub %s, %s, %s" s s1 reg]
      | _ -> assert false)
    | Fsub (s1, label) -> [Printf.sprintf "\tvsub.f32 %s, %s, %s" s s1 label]
    | Fdiv (s1, label) -> [Printf.sprintf "\tvdiv.f32 %s, %s, %s" s s1 label]
    | If (cmp_type, (r1, Reg r2), true_branch, false_branch) ->
      let true_label = generate_if_label () in
      let end_label = generate_if_label () in
      Printf.sprintf "\tcmp %s, %s" r1 r2 ::
      Printf.sprintf "\tb%s %s" cmp_type true_label ::
      List.concat (List.map generate_asm_regt false_branch) @
      Printf.sprintf "\tb %s" end_label ::
      Printf.sprintf "\t%s:" true_label ::
      List.concat (List.map generate_asm_regt true_branch) @
      Printf.sprintf "\t%s:" end_label ::
      Printf.sprintf "\tmov %s, r0" s :: []
    
    | If (cmp_type, (r1, Int n), true_branch, false_branch) ->
      let true_label = generate_if_label () in
      let end_label = generate_if_label () in
      let cmp_instruction =
        if n <= 255 then
          Printf.sprintf "\tcmp %s, #%d" r1 n
        else
          Printf.sprintf "\tldr r12, =%d\n\tcmp %s, r12" n r1
      in

      let mov_instruction =
        match s.[0] with
        | 'r' -> Printf.sprintf "\tmov %s, r0" s
        | _   -> Printf.sprintf "\tvmov.f32 %s, s0" s
      in

      cmp_instruction ::
      Printf.sprintf "\tb%s %s" cmp_type true_label ::
      List.concat (List.map generate_asm_regt false_branch) @
      Printf.sprintf "\tb %s" end_label ::
      Printf.sprintf "\t%s:" true_label ::
      List.concat (List.map generate_asm_regt true_branch) @
      Printf.sprintf "\t%s:" end_label ::
      mov_instruction :: []
    | Call (func_name, nb_params) ->

      let first_element = match !sp_values with
      | hd :: _ -> hd
      | [] -> -1 in

      if first_element = -1 then
          assert false;

      let temp_loads = ref [] in
      for i = 0 to min 4 (nb_params - 1) do
        let param_reg = "r" ^ string_of_int i in
        let param_offset = (i + 1) * 4 in
        let param_address = "-" ^ string_of_int param_offset in
        temp_loads := !temp_loads @ [Printf.sprintf "\tldr %s, [fp, #%s]" param_reg param_address];
      done;

      let instructions =
        if !pushed_vars = 1 then
          begin
            pushed_vars := 0;
            if first_element < 255 then
              [Printf.sprintf "\tsub sp, fp, #%d" first_element]
            else
              let label = generate_num_label () in
              consts := !consts @ [label ^ ": .word " ^ string_of_int (first_element * 4) ^ "\n"];
              ["\tldr r12, " ^ label;
               "\tsub sp, fp, r12"]
          end
        else
          [] 
      in 
      
      let mov_instruction =
        match s.[0] with
        | 'r' -> Printf.sprintf "\tmov %s, r0" s
        | _   -> Printf.sprintf "\tvmov.f32 %s, s0" s
      in
        
      [ Printf.sprintf "\tpush {r4-r10}";
        Printf.sprintf "\tbl %s" func_name;
        Printf.sprintf "\tpop {r4-r10}";
        mov_instruction ]
        @ instructions @ !temp_loads;

    | CallClo (reg, nb_params) ->

      let first_element = match !sp_values with
      | hd :: _ -> hd
      | [] -> -1 in

      if first_element = -1 then
          assert false;


      let temp_loads = ref [] in
      for i = 0 to min 4 (nb_params - 1) do
        let param_reg = "r" ^ string_of_int i in
        let param_offset = (i + 1) * 4 in
        let param_address = "-" ^ string_of_int param_offset in
        temp_loads := !temp_loads @ [Printf.sprintf "\tldr %s, [fp, #%s]" param_reg param_address];
      done;

      let instructions =
        if !pushed_vars = 1 then
          begin
            pushed_vars := 0;
            if first_element < 255 then
              [Printf.sprintf "\tsub sp, fp, #%d" first_element]
            else
              let label = generate_num_label () in
              consts := !consts @ [label ^ ": .word " ^ string_of_int (first_element * 4) ^ "\n"];
              ["\tldr r12, " ^ label;
               "\tsub sp, fp, r12"]
          end
        else
          [] 
      in

      let mov_instruction =
        match s.[0] with
        | 'r' -> Printf.sprintf "\tmov %s, r0" s
        | _   -> Printf.sprintf "\tvmov.f32 %s, s0" s
      in
  
      [ Printf.sprintf "\tpush {r4-r10}";
        Printf.sprintf "\tblx r12";
        Printf.sprintf "\tpop {r4-r10}";
        mov_instruction]
        @ instructions @ !temp_loads;
    | Adresse a -> 
      if abs(int_of_string a) <= 255 then
        [Printf.sprintf "\tadd %s, fp, #%s" s a]
      else
        [Printf.sprintf "\tldr r12, =#%s" a; Printf.sprintf "\tadd %s, fp, r12" s]
    | MemGet (s1, adr, nb_params) -> 
      if s1 = "%self" then
        begin
          let offset = ref 36 in
          if nb_params > 4 then
            offset := !offset + ((nb_params - 4) * 4);
    
          [Printf.sprintf "\tldr r12, [fp, #%d]" !offset;
            Printf.sprintf "\tldr %s, [r12, #%s]" s adr]
        end
      else
        if s.[0] = 'r' then
          [Printf.sprintf "\tldr %s, [%s, #%s]" s s1 adr]
        else
          begin
            if s1.[0] = 'r' then
              [Printf.sprintf "\tvldr.f32 %s, [%s, #%s]" s s1 adr]
            else
              [Printf.sprintf "\tvldr.f32 %s, [r12, #%s]" s adr]
          end
    | Label l -> 
      if s.[0] = 'r' then
        [Printf.sprintf "\tldr %s, =%s" s l]
      else
        [Printf.sprintf "\tldr r12, =%s" l]
    | Neg s1 -> [Printf.sprintf "\tneg %s, %s" s s1]
    | MemGetTab (adrReg, idxReg) ->
      [Printf.sprintf "\tmov r12, %s" idxReg;
       Printf.sprintf "\tlsl r12, r12, #2";
       Printf.sprintf "\tldr %s, [%s, r12]" s adrReg]
    | Unit -> 
      if s.[0] = 'r' then
        [Printf.sprintf "\tmov %s, #0" s]
      else
        []
    | _ -> assert false)
| Exp exp ->
(match exp with
  | If (cmp_type, (r1, Reg r2), true_branch, false_branch) ->
    let true_label = generate_if_label () in
    let end_label = generate_if_label () in
    Printf.sprintf "\tcmp %s, %s" r1 r2 ::
    Printf.sprintf "\tb%s %s" cmp_type true_label ::
    List.concat (List.map generate_asm_regt false_branch) @
    Printf.sprintf "\tb %s" end_label ::
    Printf.sprintf "\t%s:" true_label ::
    List.concat (List.map generate_asm_regt true_branch) @
    Printf.sprintf "\t%s:" end_label :: []
  
  | If (cmp_type, (r1, Int n), true_branch, false_branch) ->
    let true_label = generate_if_label () in
    let end_label = generate_if_label () in
    let cmp_instruction =
      if n <= 255 then
        Printf.sprintf "\tcmp %s, #%d" r1 n
      else
        Printf.sprintf "\tldr r12, =%d\n\tcmp %s, r12" n r1
    in
    cmp_instruction ::
    Printf.sprintf "\tb%s %s" cmp_type true_label ::
    List.concat (List.map generate_asm_regt false_branch) @
    Printf.sprintf "\tb %s" end_label ::
    Printf.sprintf "\t%s:" true_label ::
    List.concat (List.map generate_asm_regt true_branch) @
    Printf.sprintf "\t%s:" end_label :: [] 
  | Int n ->
    if n <= 255 then
      [Printf.sprintf "\tmov r0, #%d" n]
    else
      [Printf.sprintf "\tldr r0, =#%d" n] 
  | Reg reg ->
      if reg.[0] = 'r' then
        begin
          if reg = "r0" then
            []
          else
            [Printf.sprintf "\tmov r0, %s" reg]
        end
      else
        [Printf.sprintf "\tvmov.f32 s0, %s" reg]     
  | Add (s1, expr) ->
    (match expr with
    | Int n -> 
      if n <= 255 then
        [Printf.sprintf "\tadd r0, %s, #%d" s1 n]
      else
        [Printf.sprintf "\tldr r0, =#%d" n; Printf.sprintf "\tadd r0, %s, r0" s1]
    | Reg reg -> 
      if s1 = reg && s1 = "r0" then
        [Printf.sprintf "\tlsl %s, %s, #1" s1 reg]
      else
        [Printf.sprintf "\tadd r0, %s, %s" s1 reg]
    | _ -> assert false)
  | Fadd (s1, label) -> [Printf.sprintf "\tvadd.f32 r0, %s, %s" s1 label]
  | Sub (s1, expr) ->
    (match expr with
    | Int n -> 
      if n <= 255 then
        [Printf.sprintf "\tsub r0, %s, #%d" s1 n]
      else
        [Printf.sprintf "\tldr r0, =#%d" n; Printf.sprintf "\tsub r0, %s, r0" s1]
    | Reg reg -> 
      if s1 = reg && s1 = "r0" then
        [Printf.sprintf "\tlsl %s, %s, #1" s1 reg]
      else
        [Printf.sprintf "\tsub r0, %s, %s" s1 reg]      
    | _ -> assert false)
  | Fsub (s1, label) -> [Printf.sprintf "\tvsub.f32 r0, %s, %s" s1 label]
  | Fdiv (s1, label) -> [Printf.sprintf "\tvdiv.f32 r0, %s, %s" s1 label]
  | Call (func_name, nb_params) ->

    let first_element = match !sp_values with
        | hd :: _ -> hd
        | [] -> -1 in

      if first_element = -1 then
          assert false;

    let temp_loads = ref [] in
    for i = 1 to min 3 (nb_params - 1) do
      let param_reg = "r" ^ string_of_int i in
      let param_offset = (i + 1) * 4 in
      let param_address = "-" ^ string_of_int param_offset in
      temp_loads := !temp_loads @ [Printf.sprintf "\tldr %s, [fp, #%s]" param_reg param_address];
    done;

    let instructions =
      if !pushed_vars = 1 then
        begin
          pushed_vars := 0;
          if first_element < 255 then
            [Printf.sprintf "\tsub sp, fp, #%d" first_element]
          else
            let label = generate_num_label () in
            consts := !consts @ [label ^ ": .word " ^ string_of_int (first_element * 4) ^ "\n"];
            ["\tldr r12, " ^ label;
             "\tsub sp, fp, r12"]
        end
      else
        [] 
    in  

    [ Printf.sprintf "\tpush {r4-r10}";
      Printf.sprintf "\tbl %s" func_name;
      Printf.sprintf "\tpop {r4-r10}"] 
      @ instructions @ !temp_loads;
      
  | CallClo (reg, nb_params) ->

    let first_element = match !sp_values with
        | hd :: _ -> hd
        | [] -> -1 in

      if first_element = -1 then
          assert false;

    let temp_loads = ref [] in
    for i = 1 to min 3 (nb_params - 1) do
      let param_reg = "r" ^ string_of_int i in
      let param_offset = (i + 1) * 4 in
      let param_address = "-" ^ string_of_int param_offset in
      temp_loads := !temp_loads @ [Printf.sprintf "\tldr %s, [fp, #%s]" param_reg param_address];
    done;

    let instructions =
      if !pushed_vars = 1 then
        begin
          pushed_vars := 0;
          if first_element < 255 then
            [Printf.sprintf "\tsub sp, fp, #%d" first_element]
          else
            let label = generate_num_label () in
            consts := !consts @ [label ^ ": .word " ^ string_of_int (first_element * 4) ^ "\n"];
            ["\tldr r12, " ^ label;
             "\tsub sp, fp, r12"]
        end
      else
        [] 
    in  

    [ Printf.sprintf "\tpush {r4-r10}";
      Printf.sprintf "\tblx r12";
      Printf.sprintf "\tpop {r4-r10}"
    ] @ instructions @ !temp_loads;
  | Label l -> [Printf.sprintf "\tldr r0, =%s" l]
  | Neg s1 -> [Printf.sprintf "\tneg r0, %s" s1]
  | Unit -> []
  | _ -> assert false)
| Store (Reg reg, mem) -> 
  if reg.[0] = 'r' then
    [Printf.sprintf "\tstr %s, [fp, #%s]" reg mem]
  else
    [Printf.sprintf "\tvstr.f32 %s, [fp, #%s]" reg mem]
| Load (s, Reg reg) ->
  if reg.[0] = 'r' then  
    [Printf.sprintf "\tldr %s, [fp, #%s]" reg s]
  else 
    [Printf.sprintf "\tvldr.f32 %s, [fp, #%s]" reg s]
| MemAssign (adrReg, valToAdd, idx) -> 
  [Printf.sprintf "\tmov r12, %s" idx;
   Printf.sprintf "\tlsl r12, r12, #2";
   Printf.sprintf "\tstr %s, [%s, r12]" valToAdd adrReg]
| LoadReg (s, Reg reg) -> [Printf.sprintf "\tldr %s, [%s]" s reg]
| Push (r) -> 
  pushed_vars := 1;
  [Printf.sprintf "\tpush {%s}" r]

| _ -> assert false

(* Function which will calculate the prologue SP value of a function,
  and start the code generation of the function's body *)
and generate_asm_fun_internal : reg_function -> string list = fun { name; body } ->
  let rec extract_negative_sizes_regt : regt -> int list = function
  | Let (_, If (_, _, rts1, rts2)) | Exp (If (_, _, rts1, rts2)) ->
    extract_negative_sizes_regt_list rts1 @ extract_negative_sizes_regt_list rts2
  | Store (_, address_str) ->
    begin
      try
        let num = int_of_string address_str in
        if num < 0 then [num] else []
      with
      | Failure _ -> []
    end
  | _ -> []

  and extract_negative_sizes_regt_list rts =
    List.flatten (List.map extract_negative_sizes_regt rts)
  in

  let extract_negative_sizes body =
    List.flatten (List.map extract_negative_sizes_regt body)
  in

  let negative_sizes = extract_negative_sizes body in
  let min_negative_size =
    match negative_sizes with
    | [] -> 0
    | _ -> List.fold_left min max_int negative_sizes
  in
  let size = abs min_negative_size in

  sp_values := size :: !sp_values;

  [Printf.sprintf "\n%s:" name]
  @ generate_prologue size
  @ List.concat (List.map generate_asm_regt body)
  @ generate_epilogue

(* Generates the prologue *)
and generate_prologue size =
  if size <= 255 then
    ["\tpush {fp, lr}"; "\tadd fp, sp, #0"; "\tsub sp, sp, #" ^ string_of_int size]
  else
    let label = generate_num_label () in
    consts := !consts @ [label ^ ": .word " ^ string_of_int size ^ "\n"];
    ["\tpush {fp, lr}"; "\tadd fp, sp, #0"; "\tldr sp, " ^ label;
                "\tsub sp, fp, sp"]
  
(* Generates the epilogue *)
and generate_epilogue =
  match !sp_values with
  | _ :: rest ->
    sp_values := rest;
    ["\tadd sp, fp, #0"; "\tpop {fp, lr}"; "\tbx lr\n"]
  | [] ->
    ["\tadd sp, fp, #0"; "\tpop {fp, lr}"; "\tbx lr\n"]


let generate_asm_reg (defs: letregdef list) : string list =
  match defs with
  | [] -> []
  | _ ->
    let rec generate_asm_internal acc = function
      | [] -> acc
      | hd :: tl ->
        match hd with
        | Fun f when f.name = "main" ->
          let asm_hd = generate_asm_fun_internal f in
          generate_asm_internal (asm_hd @ acc) tl
        | Fun f ->
          let asm_hd = generate_asm_fun_internal f in
          generate_asm_internal (acc @ asm_hd) tl
        | LetFloatReg (s, f) -> 
          floats := !floats @ [s ^ ": .float " ^ f];
          generate_asm_internal (acc) tl
    in
    let asm_code = generate_asm_internal [] defs in !header @ !consts @ !floats @ asm_code
  