(*                                                                         *)
(*   A of Conservative Backfilling scheduler with some additional features *)
(*                                                                         *)
(* Features: *)
(* - conservative backfilling :-) *)
(* - resource matching*)
(* - insertion of previously scheduled jobs *)
(* - multiple resource requests *) (* NOT TESTED *)
(* - multiple resource types *) (* NOT TESTED *)
(* - job container *) (* NOT TESTED *)
(* - dependencies *) (* NOT TESTED *)
(* - security_time_overhead *) 
(* *)
(* Not supported features: *)
(* - moldable jobs (use only first request set*)
(* - timesharing *)
(* - job array *)
(* - fairesharing *)
(* - suspend/resume, desktop compting feature do we need do address them in main scheduler ??? *)
(* - no errors catching/namming *)
(* - ordering in resources selection *)

(* TODO need   can't scheduled job ->  to error state ??? *)

open Int64
open Interval
open Types_ts
open Hierarchy

type slot = {
	time_s : time_t;
	time_e : time_t;
	set_of_res : set_of_resources;
  ts_i : (string * string * set_of_resources) list;
  ph_i : (string * set_of_resources) list;
}

let itvs_to_string itvs = let itv2str itv = Printf.sprintf "[%d,%d]" itv.b itv.e  in
              "itvs:={ " ^  (String.concat ", " (List.map itv2str itvs)) ^ "}\n" 

let ts_to_string x = let ts2str a = let (user, jb_name, itvs) = a in "(" ^ user ^ "," ^ jb_name ^ "," ^ (itvs_to_string itvs) ^ ")\n"
                      in
                      (String.concat ", " (List.map ts2str x))

let slot_to_string slot =  "slot: time_s " ^ (to_string slot.time_s) ^ ", time_e:" ^ (to_string slot.time_e) ^
                           (itvs_to_string slot.set_of_res) ^ (ts_to_string slot.ts_i)

let slots_to_string slots =  "["^(String.concat "|" (List.map slot_to_string slots))^"]"

let slot_max nb_res = {time_s = zero; time_e = max_int; set_of_res = [{b = 1; e = nb_res}]; ts_i = []; ph_i = []}

(*                                  *)
(* find_first_contiguous_slots_time *)
(* where job can fit in time        *)

(* provides contiguous_slots which fit job_walltime and retrieve slots list *)

let find_contiguous_slots_time slot_l jbs = (* TODO optimize *)
  (*  take into account time_b *)
	let rec find_ctg_slots slots ctg_slots prev_slots = match slots with
		| s::n when (s.time_e >= (add (add jbs.time_b jbs.w_time) minus_one)) -> (ctg_slots @ [s], prev_slots , n)
		| s::n when ((add s.time_e one) <> (List.hd n).time_s) -> 
			 jbs.time_b <- (List.hd n).time_s;
			 find_ctg_slots n [] (prev_slots @ ctg_slots @ [s])
		| s::n -> find_ctg_slots n (ctg_slots @ [s]) prev_slots
 		| _ -> failwith "Not contiguous job is too long (BUG??)";

		in let next_slot_time_s = (List.hd slot_l).time_s in
			if jbs.time_b < next_slot_time_s then jbs.time_b <- next_slot_time_s;
	  	find_ctg_slots slot_l [] [];;

(* No exclusive hierarchy assignement  TODO why No exclusive ???*) (* TODO: to adapt for moldable *)
(* TODO: only need of jreq simply adaptation for moldable support ??? job -> jrq  *)

let find_resource_hierarchies_job itv_slot jrq hy_levels = 
  let rec requests_iter result hys r_rqts cts = match (hys, r_rqts, cts) with
    | ([],[],[]) -> List.flatten (List.rev result) (* TODO to optimze ??? *)
    | (x::n,y::m,z::o) -> 
      begin 
        let h = List.map (fun k -> try List.assoc k hy_levels with  Not_found -> failwith ("Can't find corresponding hierarchy level, HIERARCHY_LABELS configuration variable must be completed: "^k)) x in
        let itv_cts_slot = inter_intervals itv_slot z in
        let sub_result = find_resource_hierarchies_scattered itv_cts_slot h y in
        match sub_result with
          | [] -> []
          | res -> requests_iter (res::result) n m o
      end
    | (_,_,_) -> failwith "Not possible to be here"
  in requests_iter [] jrq.hy_level_rqt jrq.hy_nb_rqt jrq.constraints;;

let inter_slots slots =
  let rec iter_slots sls itv = match sls with
    | x::n -> let itv1 = inter_intervals itv x.set_of_res in iter_slots n itv1 
    | [] -> itv
  in  iter_slots (List.tl slots) (List.hd slots).set_of_res;; 

(*                                                                              *)
(* extract available resources accordingly to user/jobname for timesharing case *)
(*                                                                              *)
let slot2res_ts slot user jobname =
  let inter_ts accu ts_i = match ts_i with
  ("*","*",res)                                  ->  add_intervals accu res
  | (u,"*",res) when (u = user)                  ->  add_intervals accu res 
  | ("*",j,res) when (j = jobname)               ->  add_intervals accu res 
  | (u,j,res)   when (u = user) && (j = jobname) -> add_intervals accu res 
  | (_,_,_)                                      -> accu
  in List.fold_left inter_ts slot.set_of_res slot.ts_i 

(*                                                                             *) 
(* add placeholder resource accordingly to the presence of ph_name in the slot *)
(*                                                                             *)

let slot2res_ph res slot ph_name =
   let res_ph = try List.assoc ph_name slot.ph_i with  Not_found -> [] in
     let a = add_intervals res_ph res in
      (* Conf.log ("slot2res_ph:" ^ (itvs_to_string  a) ); *)  
      a
(*                                                                                                           *)
(* extract common available resources form list of slots and to accordingly user/jobname in timesharing case *)
(* and placehodler                                                                                           *)

let inter_slots_ts slots user jobname =
  let rec iter_slots_ts sls itv = match sls with
    | x::n -> let itv1 = inter_intervals itv x.set_of_res in iter_slots_ts n itv1 
    | [] -> itv
   in iter_slots_ts (List.tl slots) (slot2res_ts (List.hd slots) user jobname);; 
(*
let s1 = {time_s = 0L; time_e = 10L; set_of_res = [{b = 1; e = 10}]; ts_i = [("*","*", [{b = 5; e = 15}])]};;
let s2 = {time_s = 0L; time_e = 10L; set_of_res = [{b = 1; e = 10}]; ts_i = [("*","*", [{b = 5; e = 15}]); ("*","zop", [{b = 5; e = 20}] ) ]};;
let s3 = {time_s = 0L; time_e = 10L; set_of_res = [{b = 1; e = 10}]; ts_i = [("b","b", [{b = 5; e = 15}])  ]};;

inter_slots_ts [s1] "yop" "poy";;
inter_slots_ts [s2] "*" "*";;

*)
let inter_slots_ts_ph slots user jobname ph ph_name =
  let slot2res_ts_ph slt =  if (ph=Use_Placeholder) then
                              slot2res_ph (slot2res_ts slt user jobname) slt ph_name
                            else
                              slot2res_ts slt user jobname
  in
  let rec iter_slots_ts sls itv = match sls with
    | x::n -> let itv1 = inter_intervals itv x.set_of_res in iter_slots_ts n itv1 
    | [] -> itv
   in iter_slots_ts (List.tl slots) (slot2res_ts_ph (List.hd slots));; 

(*                                              *)
(* find_first_suitable_contiguous_slots for job *) 
(* /!\ NOT moldable version                     *)
(* TODO; to modify to support BEST -2 and ALL -1    // TODO done ???  *)

let find_first_suitable_contiguous_slots slots j hy_levels = (* non moldable*)
(*
  Conf.log ("Nb slot: " ^ (string_of_int (List.length slots))) ;
  Conf.log ("Slot: "^(slots_to_string slots));   
*)
	let rec find_suitable_contiguous_slots slot_l pre_slots job =
	   	let (next_ctg_time_slots, prev_slots, remain_slots) = find_contiguous_slots_time slot_l job  in
      let itv_inter_slots = if (job.ts || (job.ph = Use_Placeholder)) then 
                              inter_slots_ts_ph next_ctg_time_slots job.ts_user job.ts_jobname job.ph job.ph_name
                            else
                              inter_slots next_ctg_time_slots                      
      in (* TODO add test job.ts *)
      (* Conf.log ("before :  find_resource_hierarchies_job "); *)
      let itv_res_assignement = find_resource_hierarchies_job itv_inter_slots (List.hd job.rq) hy_levels in
      (* Conf.log ("after :  find_resource_hierarchies_job "); *)
      match  itv_res_assignement with
        | [] -> find_suitable_contiguous_slots (List.tl next_ctg_time_slots @ remain_slots) 
                                               (pre_slots @ prev_slots @ [List.hd next_ctg_time_slots]) job
        | itv -> (* Conf.log ("\n itv: " ^ (itvs_to_string itv) ^ 
                            "\n next_ctg_time_slots: " ^ (slots_to_string  next_ctg_time_slots) ^
                            "\n pre_slots : " ^ (slots_to_string pre_slots) ^
                            "\n  prev_slots: " ^ (slots_to_string prev_slots) ^
                            "\n  remain_slots: " ^ (slots_to_string remain_slots));
                  *)
                (itv, next_ctg_time_slots, (pre_slots @ prev_slots), remain_slots)
		in
			find_suitable_contiguous_slots slots [] j ;;


(*******************************************************)
(* split slot accordingly with job resource assignment *)
(* new slot A + B + C (A, B and C can be null)         *)
(*  ------
   |A|B|C|
   |A|J|C|
   |A|B|C|
    ------ *)

(* generate A slot *) (* slot before job's begin *)
let slot_before_job_begin slot jbs = {
	time_s = slot.time_s;
	time_e = add jbs.time_b minus_one;
	(* nb_free_res = slot.nb_free_res; TOREMOVE*)
	set_of_res = slot.set_of_res;
  ts_i = slot.ts_i;
  ph_i = slot.ph_i;
}

(* generate B slot *) 
let slot_during_job slot jbs = {
  time_s = max jbs.time_b slot.time_s;
  time_e = min (add (add jbs.time_b  jbs.w_time) minus_one) slot.time_e ;
	set_of_res = sub_intervals slot.set_of_res jbs.set_of_rs;
  ts_i = slot.ts_i;
  ph_i = slot.ph_i;
}

(* generate B slot with timesharing support *) 
let slot_during_job_ts slot jbs = {
		time_s = max jbs.time_b slot.time_s;
		time_e = min (add (add jbs.time_b  jbs.w_time) minus_one) slot.time_e ;
		set_of_res = sub_intervals slot.set_of_res jbs.set_of_rs;
    ts_i =  if (jbs.ts) then (* timesharing case *)
              (jbs.ts_user,jbs.ts_jobname,jbs.set_of_rs)::slot.ts_i
            else
              slot.ts_i
    ;
    ph_i = match jbs.ph with
        Use_Placeholder ->  if (List.mem_assoc jbs.ph_name slot.ph_i) then
                              let updated_set_of_res =  sub_intervals (List.assoc jbs.ph_name slot.ph_i) jbs.set_of_rs in
                                (jbs.ph_name, updated_set_of_res)::(List.remove_assoc jbs.ph_name slot.ph_i); (* update the right pairs (ph_name,st_of_rs) *)
                            else
                              slot.ph_i; 
      | Set_Placeholder -> (* Conf.log "slot_during_job_ts Set_Placeholder"; *)
                           (jbs.ph_name,jbs.set_of_rs)::slot.ph_i;
      | No_Placeholder  -> slot.ph_i;
}

(* generate C slot *) (* slot after job's end *)

let slot_after_job_end slot jbs = {
	time_s = add jbs.time_b jbs.w_time ;
	time_e = slot.time_e  ;
	set_of_res = slot.set_of_res;
  ts_i = slot.ts_i;
  ph_i = slot.ph_i;
}

let split_slots slots jbs =
(* TODO to rm 
  if (jbs.ts) then
        Conf.log("split_slots jbs.ts TRUE")
      else
        Conf.log ("split_slots jbs.ts FALSE");
*)
  let add_no_empty s ac = match s.set_of_res,s.ts_i,s.ph_i with
    [],[],[] -> ac
    | _,_,_ -> s::ac
  in
  let rec split_slts slts accu = match slts with 
    [] ->  accu
    | slt ::l ->  if jbs.time_b > slt.time_s then (* AAA *)
			              if  (add (add jbs.time_b jbs.w_time) minus_one) > slt.time_e then
					            (* A+B *)
					            let a = add_no_empty (slot_before_job_begin slt jbs) (add_no_empty (slot_during_job_ts slt jbs) accu) in
                        split_slts l a
			              else
				 		(* A+B+C *)
						let a = add_no_empty (slot_before_job_begin slt jbs) (add_no_empty (slot_during_job_ts slt jbs) (add_no_empty (slot_after_job_end slt jbs) accu)) in
              split_slts l a
		else
			if (add (add jbs.time_b  jbs.w_time) minus_one) >= slt.time_e then
			  let a = add_no_empty (slot_during_job_ts slt jbs) accu in
          split_slts l a
			else
				(* B+C *) 
				let a =add_no_empty ( slot_during_job_ts slt jbs) (add_no_empty (slot_after_job_end slt jbs ) accu) in
          split_slts l a            
    in split_slts slots []

(*                                                                                                 *)
(* assign_resources_job_split_slots:                                                               *)
(* Assign resources to a job and update the list of slots accordingly by splitting concerned slots *)
(*                                                                                                 *)

let assign_resources_job_split_slots job slots hy_levels = 
	let (resource_assigned, ctg_slots, prev_slots, remain_slots) = find_first_suitable_contiguous_slots slots job hy_levels in
	  job.set_of_rs <- resource_assigned;
		(job, prev_slots @ (split_slots ctg_slots job) @ remain_slots);;

(* moldable version *)
let assign_resources_mld_job_split_slots job slots hy_levels =
  Conf.log "assign_resources_mld_job_split_slots";

(* TODO Modify see use_rq / rq in type_ts.ml *)
  let new_job moldable_id walltime constraints hy_level_rqt hy_nb_rqt =
        { (* construct job TODO: VERIFY that we don't need to copy all fields for remains steps to final assignement ??? *)
          jobid = job.jobid;  
          jobstate = ""; (* no need *)
          moldable_id = moldable_id;
          time_b = Int64.zero;
          w_time = walltime;
          types = [];
          set_of_rs = [];
          ts = job.ts; ts_user = job.ts_user; ts_jobname = job.ts_jobname;
          ph = job.ph; ph_name = job.ph_name;
          user = "";
          project = "";
          rq = [{mlb_id=moldable_id; walltime=walltime; constraints=constraints; hy_level_rqt=hy_level_rqt; hy_nb_rqt=hy_nb_rqt}]
        };
    in
  let rec moldable_find_earliest_finish_contiguous_slots time_f (j_req_lst: jreq list) f_j f_res_asgnmt f_ctg_slots f_prev_slots f_remain_slots = match j_req_lst with
    [] -> (f_j,f_res_asgnmt, f_ctg_slots, f_prev_slots, f_remain_slots)
    | req::reqs ->
        let j = new_job req.mlb_id req.walltime req.constraints req.hy_level_rqt req.hy_nb_rqt in
        let (resource_assigned, ctg_slots, prev_slots, remain_slots) = find_first_suitable_contiguous_slots slots j hy_levels in
          let j_time_f = add j.time_b req.walltime in (* compute the finish time for this moldable *)
            if (j_time_f < time_f) then (* this moldable finish earlier keep it *)
              moldable_find_earliest_finish_contiguous_slots j_time_f reqs j resource_assigned ctg_slots prev_slots remain_slots
            else
              (* keep the previous one *)
              moldable_find_earliest_finish_contiguous_slots time_f reqs f_j f_res_asgnmt f_ctg_slots f_prev_slots f_remain_slots
        in 
      let (final_job,final_resource_assigned, final_ctg_slots, final_prev_slots, final_remain_slots ) = 
             moldable_find_earliest_finish_contiguous_slots 2147483648L job.rq (new_job 0 0L [] [] [])  [] [] [] [] 
        in
          (* Conf.log ("final_resource_assigned;" ^(itvs_to_string final_resource_assigned) ); *)
          final_job.set_of_rs <- final_resource_assigned;
          (final_job, final_prev_slots @ (split_slots final_ctg_slots final_job) @ final_remain_slots);;

(*                                                                                                  *)
(* Schedule loop with support for jobs container - can be recursive (recursivity has not be tested) *)
(* plus dependencies support                                                                        *)
(* * actual schedule function used *                                                                *)

 let schedule_id_jobs_ct_dep h_slots h_jobs hy_levels h_jobs_dependencies h_req_jobs_status jids security_time_overhead =

  let find_slots s_id =  try Hashtbl.find h_slots s_id with Not_found -> failwith "Can't Hashtbl.find slots (schedule_id_jobs_ct)" in
  let find_job j_id = try Hashtbl.find h_jobs j_id with Not_found -> failwith "Can't Hashtbl.find job (schedule_id_jobs_ct)" in 
  let test_type job job_type = try (true, (List.assoc job_type job.types)) with Not_found -> (false,"") in

  (* dependencies evaluation *)
  let test_no_dep jid =  try (false, (Hashtbl.find h_jobs_dependencies jid)) with Not_found -> (true,[]) in

(*
  let test_job_scheduled = try (Hashtbl.find h_jobs j)  with Not_found -> failwith "Can't Hashtbl.find h_jobs (test_job_scheduled )" in
*)
    
  let dependencies_evaluation j_id job_init =
    (* are there denpendencies*)
    let (tst_no_dep, deps) = test_no_dep j_id in
    if tst_no_dep then
      (false, job_init) (* don't skip, no dep *)
    else
      let rec jobs_required_iter dependencies = match dependencies with
        | [] -> (false, job_init)
        | jr_id::n -> let jrs =  try (Hashtbl.find h_req_jobs_status jr_id) with Not_found -> failwith "Can't Hashtbl.find jr in h_req_jobs_status" in
                      if (jrs.jr_state != "Terminated") then
                        let jsched = find_job jr_id in
                          (* test is job scheduled*)
                          if (jsched.set_of_rs != []) then
                            begin
                              if (add jsched.time_b jsched.w_time) > job_init.time_b then job_init.time_b <- (add jsched.time_b jsched.w_time);
                              jobs_required_iter n
                            end
                          else
                            (* job message: "Cannot determine scheduling time due to dependency with the job $d"; *)
                            (* oar_debug("[oar_sched_gantt_with_timesharing] [$j->{job_id}] $message\n"); *)
                            (true, job_init) (* skip *)
                      else (* job is Terminated *)
                        if (jrs.jr_jtype = "PASSIVE") && (jrs.jr_exit_code != 0) then
                          (* my $message = "Cannot determine scheduling time due to dependency with the job $d (exit code != 0)";
                             OAR::IO::set_job_message($base,$j->{job_id},$message);
                             OAR::IO::set_job_scheduler_info($base,$j->{job_id},$message);
                             oar_debug("[oar_sched_gantt_with_timesharing] [$j->{job_id}] $message\n");
                          *)
                          (true, job_init) (* skip *)
                        else
                          jobs_required_iter n
      in
        jobs_required_iter deps
 
  in
  (* assign ressource for all waiting jobs *)
  let rec assign_res_jobs j_ids scheduled_jobs nosched_jids = match j_ids with
		| [] -> (List.rev scheduled_jobs, List.rev nosched_jids)
		| jid::n -> let j_init = find_job jid in
                let (test_skip, j) = dependencies_evaluation jid j_init in
                let (test_inner, value_in) = test_type j "inner" in
                  let num_set_slots = if test_inner then (int_of_string value_in) else 0 in
(*                let num_set_slots = if test_inner then (try int_of_string value with _ -> 0) else 0 in *)(* job_error *)
                  begin
                    let (test_container, value) = test_type j "container" in
                      let current_slots = find_slots num_set_slots in
(* TODO: test moldable *)
                      let (ok, ns_jids, (job, updated_slots) ) = try (true, nosched_jids, assign_resources_mld_job_split_slots j current_slots hy_levels) 
                                                      with _ -> (false, (jid::nosched_jids), (j_init, current_slots))
                                                      (*  with x -> raise x *)
(*
                      let (ok, ns_jids, (job, updated_slots) ) = try (true, nosched_jids, assign_resources_job_split_slots j current_slots hy_levels) 
                                                        with _ -> (false, (jid::nosched_jids), (j_init, current_slots)) 
*)
                      in
                        if ok then
                          begin 
                            (* Conf.log ("Assign_resources_mld_job_split_slots OK"); *)
                            Hashtbl.replace h_slots num_set_slots updated_slots; (* TODO IS NO NEED OR MUST BE OPTIMISED ??? *) 
                            if test_container then
                              (* create new slot / container *) (* substract j.walltime security_time_overhead *)
                              Hashtbl.add h_slots jid [{
                                time_s = job.time_b; 
                                time_e = add job.time_b (sub job.w_time security_time_overhead); 
                                set_of_res=job.set_of_rs;
                                ts_i=[];
                                ph_i=[]}];
                              (* replace updated/assgined job in job hashtable *) 
                              Hashtbl.replace h_jobs jid job; (* TODO IS NO NEED ??? *) 

                            assign_res_jobs n (job::scheduled_jobs) ns_jids
                          end
                       else 
                        assign_res_jobs n scheduled_jobs ns_jids
                  end 
  in
    assign_res_jobs jids [] []

(* function insert previously occupied slots in slots *)
(* job must be sorted by start_time *)
(* used in kamelot for pseudo_jobs_resources_available_upto splitting *)
let split_slots_prev_scheduled_jobs slots jobs =

  let rec find_first_slot left_slots right_slots job = match right_slots with
    | x::n  when ((x.time_s > job.time_b) || ((x.time_s <= job.time_b) && (job.time_b <= x.time_e))) -> (left_slots,x,n) 
    | x::n -> find_first_slot (left_slots @ [x]) n job
    | [] -> failwith "Argl cannot failed here"

  in

  let rec find_slots_aux encompass_slots r_slots job = match r_slots with
    (* find timed slots *)
    | x::n when (x.time_e >  (add job.time_b job.w_time)) -> (encompass_slots @ [x],n) 
    | x::n -> find_slots_aux (encompass_slots @ [x]) n job
    | [] -> failwith "Argl cannot failed here"
   in

  let find_slots_encompass first_slot right_slots job =
    if (first_slot.time_e >  (add job.time_b job.w_time)) then
      ([first_slot],right_slots)
    else find_slots_aux [first_slot] right_slots job

    in

      let rec split_slots_next_job prev_slots remain_slots job_l = match job_l with
        | [] -> prev_slots @ remain_slots
        | x::n -> let (l_slots, first_slot, r_slots) = find_first_slot prev_slots remain_slots x in
                  let (encompass_slots, ri_slots) =  find_slots_encompass first_slot r_slots x in
                  let splitted_slots =  split_slots encompass_slots x in 
                    split_slots_next_job l_slots (splitted_slots @ ri_slots) n 
     in 
        split_slots_next_job [] slots jobs


(* function insert previously one scheduled job in slots *)
(* job must be sorted by start_time *)

let split_slots_prev_scheduled_one_job slots job =

  let rec find_first_slot left_slots right_slots job = match right_slots with
    | x::n  when ((x.time_s > job.time_b) || ((x.time_s <= job.time_b) && (job.time_b <= x.time_e))) -> (left_slots,x,n) 
    | x::n -> find_first_slot (left_slots @ [x]) n job 
    | [] -> failwith "Argl cannot failed here"

  in

  let rec find_slots_aux encompass_slots r_slots job = match r_slots with
    (* find timed slots *)
    | x::n when (x.time_e >  (add job.time_b job.w_time)) -> (encompass_slots @ [x],n) 
    | x::n -> find_slots_aux (encompass_slots @ [x]) n job
    | [] -> failwith "Argl cannot failed here"
   in

  let find_slots_encompass first_slot right_slots job =
    if (first_slot.time_e >  (add job.time_b job.w_time)) then
      ([first_slot],right_slots)
    else find_slots_aux [first_slot] right_slots job

    in

      let (l_slots, first_slot, r_slots) = find_first_slot [] slots job in
        let (encompass_slots, ri_slots) =  find_slots_encompass first_slot r_slots job in
          let splitted_slots =  split_slots encompass_slots job in 
            splitted_slots @ ri_slots 
(*                                                                                 *)
(* function insert previously scheduled job in slots with containers consideration *)
(* job must be sorted by ascending start_time *)

(* loop across ordered jobs' id by start_time and create new set_slots or split slots when needed *) 

let set_slots_with_prev_scheduled_jobs h_slots h_jobs ordered_id_jobs security_time_overhead =
  let find_slots s_id =  try Hashtbl.find h_slots s_id with Not_found -> failwith "Can't Hashtbl.find slots (set_slots_with_prev_scheduled_jobs)" in 
  let find_job j_id = try Hashtbl.find h_jobs j_id with Not_found -> failwith "Can't Hashtbl.find job (set_slots_with_prev_scheduled_jobs)" in 
  let test_type job job_type = try (true, (List.assoc job_type job.types)) with Not_found -> (false,"0") in
  let rec loop_jobs od_id_jobs = match od_id_jobs with
    | [] -> () (* terminated *)
    | jid::m -> let j = find_job jid in
                let (test_inner, value_in) = test_type j "inner" in
                let num_set_slots = if test_inner then (int_of_string value_in) else 0 in
                begin
                  let (test_container, value) = test_type j "container" in
                  if test_container then
                    (* create new slot / container *) (* substract j.walltime security_time_overhead *)
                    Hashtbl.add h_slots jid [{
                      time_s = j.time_b; 
                      time_e = add j.time_b (sub j.w_time security_time_overhead); 
                      set_of_res = j.set_of_rs;
                      ts_i = [];
                      ph_i = []}];
                  (* TODO perhaps we'll need to optimize split_slots_prev_scheduled_jobs...made for jobs list *) 
                  Hashtbl.replace h_slots num_set_slots (split_slots_prev_scheduled_one_job (find_slots num_set_slots) j); 
                  loop_jobs m
                end  
  in
    loop_jobs ordered_id_jobs
