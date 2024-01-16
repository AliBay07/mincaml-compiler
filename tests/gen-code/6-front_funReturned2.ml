let rec add x y =
  x + y
in
let rec sub x y =
  x - y
in
let rec make_operator x y =
  if x > y then
    add
  else
    sub
in
let a = 10 in
let b = 20 in
print_int ((make_operator a b) a b)