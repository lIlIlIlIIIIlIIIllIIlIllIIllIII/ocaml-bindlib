open Basic
open Print
open Bindlib

exception Clash
exception Nonfree

let match_one t (arities, pat, res) =
  let vars = 
    Array.map 
      (fun n -> unbox (bind lvar tl in unit Dummy))
      arities
  in 
  let pat = subst pat vars in
  let rec do_match depth t1 t2 = match t1, t2 with
    Bind(_,_,f1), Bind(_,_,f2) ->
      let c = Varint (depth) in
      do_match (depth+1) (subst f1 c) (subst f2 c)
  | Varint (n) , Varint (p) when n = p -> 
      ()
  | App(_,_,s1,ts1), App(_,_,s2,ts2) when s1 == s2 ->
      for i = 0 to s1.symbol_arity -1 do
        do_match depth ts1.(i) ts2.(i)
      done
  | UVar(tbl, index,  tl1), t2 ->
      let rec immitate tl = function
          Bind(cl, name, f) as t0->
	    if cl then
	      unit t0
      	    else
	      match f with bind var x as name in t ->
              Bind(^(^cl^),(^name^),
		   bindvar x in immitate tl t^)
 	| App(cl,_,s2, ts2) as t0 ->
	    if cl then
	      unit t0
      	    else 
              App(^(^cl^), (^false^), (^s2^),
		  lift_array (Array.map (immitate tl) ts2)^)
	| Def _ as t ->
	    unit t
        | Var (x) -> bindbox_of x
        | Varint(n) -> 
	    let rec fn pos = function
        	[] -> raise Nonfree
	      | (Varint(n1))::_ when n1 = n -> pos
	      |	_ :: suit -> fn (pos + 1) suit
	    in
	    let pos = fn 0 tl1 in
	    bnth pos tl
	| _ -> failwith "bug in immitate"
      in  
      tbl.(index) <- 
	 unbox (bind lvar tl in immitate tl t2)
  | Def(_,_,t1), t2 ->
      do_match depth t1 t2
  | t1, Def(_,_,t2) ->
      do_match depth t1 t2
  | t1, t2 ->
      raise Clash        
  in 
  do_match 0 pat t; 
  subst res vars

let par_red t =
  let rec copy = function
      Bind(cl,name, f) as t -> 
	if cl then unit t else
	match f with bind var x as name in t ->
	Bind(^(^cl^),(^name^),copy t^)
    | App(cl,normal,s, ts) as t -> 
	if cl then unit t else
	(if normal then bApp_normal else bApp) s (Array.map copy ts)
    | Def _ as t ->
	unit t
    | Var (x) -> 
	bindbox_of x
    | _ -> failwith "bug in par_red"
  in
  let rec fn did_one = function
      Bind(_, name, f) -> 
        bBind name (
	  fun x -> fn did_one (subst f (Varterm x)))
    | App(cl,false, s, ts) -> 
        let did_one' = ref false in
        let nts = Array.map (fn did_one') ts in
        let nt = 
 	  if !did_one' then begin
	    did_one := true;
            bApp s nts
	  end else begin
	    bApp_normal s nts
	  end
	in
	let nt = start_term nt in
	let rec gn = function
          [] -> 
	    copy nt
	| pat::suit -> 
	    try 
	      let res = match_one nt pat in
	      did_one := true; copy res
	    with
	      Clash | Nonfree -> gn suit
	in gn s.symbol_rewrite
    | Def(_,normal,t') as t ->
	if !normal then
	  unit t
	else begin
          let did_one' = ref false in
	  let t'' = fn did_one' t' in
	  if !did_one' then begin
	    did_one := true;
	    t''
	  end else begin
	    normal := true;
	    unit t
	  end
	end
    | App(_,true,_,_) as t ->
	copy t
    | Varterm (x) -> 
	x
    | u -> print_term u; failwith "bug in parred"
  in 
  let did_one = ref false in
  let t' = start_term (fn did_one t) in 
  !did_one, t'

let rec reduce t =
  let cont, t = par_red t in
(*  print_term t;
  print_newline ();
*)
  if cont then reduce t else t

