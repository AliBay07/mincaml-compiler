(*
inline.ml

date : 09-01-2023
*)

type definition_map = Knorm.fundef list

(* seuil de la taille d'une petite fonction *)
(* une dizaine d'opérations A LA LOUCHE *)
let max_depth = ref 10

(* Calcule la taille de la fonction en nombre de noeuds dans l'ast *)
let rec depth (e:Knorm.knorm_t) (fct_name:Id.t) : int =
  match e with
  | App (f, _) -> 
    (* si f recursive pas de remplacement : on depasse le seuil *)
    (if f = fct_name then !max_depth + 2 else 1)

  | IfEq ((x, y), k1, k2) -> 
    let d1 = depth k1 fct_name and d2 = depth k2 fct_name in  1 + d1 + d2
  | IfLE ((x, y), k1, k2) ->
    let d1 = depth k1 fct_name and d2 = depth k2 fct_name in 1 + d1 + d2
  | Let ((id,t), k1, k2) ->
    let d1 = depth k1 fct_name and d2 = depth k2 fct_name in  1 + d1 + d2
  | LetRec (fd, e) -> 
    let d1 = depth fd.body fct_name and d2 = depth e fct_name in 1 + d1 + d2
  | LetTuple (args, var, e) -> 1 + (depth e fct_name)
  | _ -> 1


  let rec replace (e:Knorm.knorm_t) (map:Alpha.epsilon) : Knorm.knorm_t =
    let eps_apply = Alpha.apply map in
    match e with
    (* nothing to do *)
    | Unit | Int _ | Float _ -> e
  
    (* find in environment *)
    | Var s -> Var (eps_apply s)
  
    (* no recursive calls *)
    | Neg x -> Neg (eps_apply x)
    | Add (x, y) -> Add (eps_apply x, eps_apply y)
    | Sub (x, y) -> Sub (eps_apply x, eps_apply y)
    | FNeg x -> FNeg (eps_apply x)
    | FAdd (x, y) -> FAdd (eps_apply x, eps_apply y)
    | FSub (x, y) -> FSub (eps_apply x, eps_apply y)
    | FMul (x, y) -> FMul (eps_apply x, eps_apply y)
    | FDiv (x, y) -> FDiv (eps_apply x, eps_apply y)
    | App (f, vars) -> App (eps_apply f, List.map eps_apply vars)
    | Get (x, y) -> Get (eps_apply x, eps_apply y)
    | Put (x, y, z) -> Put (eps_apply x, eps_apply y, eps_apply z)
    | Tuple(l) -> Tuple (List.map eps_apply l)
    | Array(x,y) -> Array (eps_apply x, eps_apply y)
  
    (* with recursive calls *)
    | IfEq ((x,y),e1,e2) -> 
      let e12 = replace e1 map and e22 = replace e2 map in
        IfEq ((eps_apply x, eps_apply y), e12, e22)
    | IfLE ((x,y),e1,e2) -> 
      let e12 = replace e1 map and e22 = replace e2 map in
        IfLE ((eps_apply x, eps_apply y), e12, e22)
  
    | Let ((s,t), e1, e2) -> 
      let e12 = replace e1 map and e22 = replace e2 map in
        Let ((s,t), e12, e22)
    | LetRec (fd, e) -> 
      LetRec ({name = fd.name; args = fd.args; body = replace fd.body map}, replace e map)
    | LetTuple (l1, v, e1) -> LetTuple (l1, eps_apply v, replace e1 map)
  

(* Main function of this module *)
let expansion (ast:Knorm.knorm_t) : Knorm.knorm_t =
  let rec inline (a:Knorm.knorm_t) (env:definition_map) : Knorm.knorm_t = 
    match a with
    | IfEq (c, e1, e2) -> IfEq (c, inline e1 env, inline e2 env)
    | IfLE (c, e1, e2) -> IfLE (c, inline e1 env, inline e2 env)
    | Let (xt, e1, e2) -> Let (xt, inline e1 env, inline e2 env)
    | LetTuple (args, var, e) -> LetTuple(args, var, inline e env)

    | LetRec (fd, e) -> 
      let in_body = inline fd.body env in
        let fdepth = depth in_body (fst fd.name) in
          if fdepth <= !max_depth then 
            LetRec({name = fd.name; args = fd.args; body = in_body}, inline e (fd::env))
          else LetRec({name = fd.name; args = fd.args; body = in_body}, inline e env)
    | App (f, vars) -> 
      (try
        let fd = List.find (fun (x:Knorm.fundef) -> fst (x.name) = f) env in
          let expr = replace fd.body 
                     (List.map2 (fun x y -> (x,y)) (List.map fst fd.args) vars) in
            Alpha.conversion expr

      with Not_found -> a)
    | _ -> a
in inline ast []