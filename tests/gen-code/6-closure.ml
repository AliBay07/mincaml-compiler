(*exemple de programme avec une closure (qui créer un additionneur) pour tester la génération de code asml et arm*)
let rec addBy x = 
  let y = 40 in
  let rec adder z = x - y + z in
  adder in
  print_int((addBy 1) 41);
  print_newline();
  print_int((addBy 0) 60);
  print_newline();
  print_int((addBy (-3)) 50)