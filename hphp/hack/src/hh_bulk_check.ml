(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the "hack" directory of this source tree.
 *
 *)

open ServerEnv

type schedule_args = {
  bin_root: Path.t;
  root: Path.t;
  naming_table: string;
  input_file: string;
  (* Number of remote workers *)
  num_remote_workers: int;
  num_local_workers: int;
  batch_size: int option;
  timeout: int;
}

type command =
  | CSchedule of schedule_args
  | CWork of unit option RemoteWorker.work_env

type command_keyword =
  | CKSchedule
  | CKWork
  | CKNone

let command_keyword_to_string (keyword : command_keyword) : string =
  match keyword with
  | CKSchedule -> "schedule"
  | CKWork -> "work"
  | CKNone -> ""

let string_to_command_keyword (str : string) : command_keyword =
  match str with
  | "schedule" -> CKSchedule
  | "work" -> CKWork
  | _ -> CKNone

let parse_command () =
  if Array.length Sys.argv < 2 then
    CKNone
  else
    string_to_command_keyword (String.lowercase_ascii Sys.argv.(1))

let parse_without_command options usage ~(keyword : command_keyword) =
  let args = ref [] in
  Arg.parse (Arg.align options) (fun x -> args := x :: !args) usage;
  match List.rev !args with
  | x :: rest when string_to_command_keyword x = keyword -> rest
  | args -> args

let parse_root (args : string list) : Path.t =
  match args with
  | [] -> Wwwroot.get None
  | [x] -> Wwwroot.get (Some x)
  | _ ->
    Printf.fprintf stderr "Error: please provide at most one root directory\n%!";
    exit 1

let validate_required_arg arg_ref arg_name =
  match !arg_ref with
  | None -> failwith (Printf.sprintf "%s is required." arg_name)
  | Some arg -> arg

let parse_schedule_args () : command =
  let timeout = ref 9999 in
  let naming_table = ref None in
  let num_remote_workers = ref 1 in
  let num_local_workers = ref Sys_utils.nbr_procs in
  let batch_size = ref None in
  let input_file = ref None in
  let set_option_arg name reference value =
    match !reference with
    | None -> reference := Some value
    | Some _ -> failwith (Printf.sprintf "Attempted to set %s twice" name)
  in
  let options =
    [
      ("--timeout", Arg.Int (fun x -> timeout := x), "The timeout");
      ( "--naming-table",
        Arg.String (set_option_arg "naming table file" naming_table),
        "input naming table SQLlite file path (required)." );
      ( "--num-remote-workers",
        Arg.Int (fun x -> num_remote_workers := x),
        "The number of remote workers (default is 1)." );
      ( "--num-local-workers",
        Arg.Int (fun x -> num_local_workers := x),
        "The number of local workers (default is the number of processors)." );
      ( "--batch-size",
        Arg.Int (set_option_arg "batch size" batch_size),
        "Remote worker batch size." );
      ( "--input-file",
        Arg.String (set_option_arg "input file" input_file),
        "Input file path that contains the list of files to type check." );
    ]
  in
  let usage = "Usage: " ^ Sys.executable_name ^ " schedule <repo_root>" in
  let args = parse_without_command options usage ~keyword:CKSchedule in
  let (root : Path.t) = parse_root args in
  let bin_root = Path.make (Filename.dirname Sys.argv.(0)) in

  CSchedule
    {
      bin_root;
      root;
      naming_table = validate_required_arg naming_table "--naming-table";
      input_file = validate_required_arg input_file "--input-file";
      num_remote_workers = !num_remote_workers;
      num_local_workers = !num_local_workers;
      batch_size = !batch_size;
      timeout = !timeout;
    }

let make_remote_server_api () :
    (module RemoteWorker.RemoteServerApi with type naming_table = unit option) =
  ( module struct
    type naming_table = unit option

    let type_check ctx files_to_check ~state_filename =
      ignore (ctx, files_to_check, state_filename);
      Errors.empty

    let load_naming_table_base ~naming_table_base =
      ignore naming_table_base;
      Ok (Some ())

    let load_naming_table_changes_since_baseline
        ctx ~naming_table ~naming_table_diff =
      ignore (ctx, naming_table, naming_table_diff);
      Ok (Some ())
  end : RemoteWorker.RemoteServerApi
    with type naming_table = unit option )

let parse_work_args () : command =
  let key = ref "" in
  let timeout = ref 9999 in
  let options =
    [
      ("--key", Arg.String (fun x -> key := x), " The worker's key");
      ("--timeout", Arg.Int (fun x -> timeout := x), " The timeout");
    ]
  in
  let usage = "Usage: " ^ Sys.executable_name ^ " work <key>" in
  let args = parse_without_command options usage ~keyword:CKWork in
  let root = parse_root args in
  let bin_root = Path.make (Filename.dirname Sys.argv.(0)) in
  let check_id = Random_id.short_string () in
  let (ctx : Provider_context.t) =
    Provider_context.empty_for_tool
      ~popt:ParserOptions.default
      ~tcopt:TypecheckerOptions.default
      ~backend:Provider_backend.Shared_memory
  in
  let server = make_remote_server_api () in
  CWork
    (RemoteWorker.make_env
       ctx
       ~bin_root
       ~check_id
       ~key:!key
       ~root
       ~timeout:!timeout
       server)

let parse_args () =
  match parse_command () with
  | CKNone
  | CKSchedule ->
    parse_schedule_args ()
  | CKWork -> parse_work_args ()

(* 
  Initialize env/genv from naming_table and create local workers 
  based on num_local_workers.
*)
let init_env_and_create_local_workers root naming_table num_local_workers =
  Tempfile.with_real_tempdir @@ fun tmp ->
  let t = Unix.gettimeofday () in
  Relative_path.set_path_prefix Relative_path.Root root;
  Relative_path.set_path_prefix Relative_path.Tmp tmp;
  let hhi_root = Hhi.get_hhi_root () in
  Hh_logger.log "Extracted hhi files to directory %s" (Path.to_string hhi_root);
  Relative_path.set_path_prefix Relative_path.Hhi hhi_root;

  let init_id = Random_id.short_string () in
  HackEventLogger.init_batch_tool ~init_id ~root ~time:t;
  let server_args = ServerArgs.default_options ~root:(Path.to_string root) in
  let (server_config, server_local_config) =
    ServerConfig.load ServerConfig.filename server_args
  in
  let hhconfig_version =
    server_config |> ServerConfig.version |> Config_file.version_to_string_opt
  in
  let sharedmem_config = ServerConfig.sharedmem_config server_config in
  let handle = SharedMem.init sharedmem_config ~num_workers:num_local_workers in
  let server_env = ServerEnvBuild.make_env server_config in
  let ctx = Provider_utils.ctx_from_server_env server_env in
  let server_env =
    {
      server_env with
      ServerEnv.naming_table = Naming_table.load_from_sqlite ctx naming_table;
    }
  in
  let t = Unix.gettimeofday () in
  let gc_control = ServerConfig.gc_control server_config in
  let workers =
    ServerWorker.make
      ~nbr_procs:num_local_workers
      gc_control
      handle
      ~logging_init:(fun () ->
        HackEventLogger.init_worker
          ~root
          ~hhconfig_version
          ~init_id:(init_id ^ "." ^ Random_id.short_string ())
          ~time:t
          ~profile_type_check_duration_threshold:0.
          ~profile_owner:(Sys_utils.logname ())
          ~profile_desc:"hh_bulk_check"
          ~max_times_to_defer:None)
  in
  let genv =
    ServerEnvBuild.make_genv
      server_args
      server_config
      server_local_config
      workers
  in
  (server_env, genv, workers)

let get_batch_size genv (batch_size : int option) =
  match batch_size with
  | Some size -> (size, size)
  | None ->
    ( ServerLocalConfig.(genv.local_config.remote_type_check.max_batch_size),
      ServerLocalConfig.(genv.local_config.remote_type_check.min_batch_size) )

(* 
  Start remote checking service with number of remote workers specified by num_remote_workers.
*)
let start_remote_checking_service genv env num_remote_workers batch_size =
  let version_specifier =
    ServerLocalConfig.(genv.local_config.remote_version_specifier)
  in

  let (max_batch_size, min_batch_size) = get_batch_size genv batch_size in
  let worker_min_log_level =
    ServerLocalConfig.(genv.local_config.remote_type_check.worker_min_log_level)
  in
  let root = Relative_path.path_of_prefix Relative_path.Root in
  let delegate_state =
    Typing_service_delegate.start
      Typing_service_types.
        {
          init_id = env.init_env.init_id;
          mergebase = env.init_env.mergebase;
          num_workers = num_remote_workers;
          root;
          server =
            ServerApi.make_local_server_api
              env.naming_table
              ~root
              ~ignore_hh_version:(ServerArgs.ignore_hh_version genv.options);
          version_specifier;
          worker_min_log_level;
        }
      (Typing_service_delegate.create ~max_batch_size ~min_batch_size ())
      ~recheck_id:env.init_env.recheck_id
  in
  delegate_state

(*
  Initialize envs, create local workers and create remote checking service delegate.
*)
let create_service_delegate (schedule_env : schedule_args) =
  let (env, genv, _) =
    init_env_and_create_local_workers
      schedule_env.root
      schedule_env.naming_table
      schedule_env.num_local_workers
  in
  let delegate_state =
    start_remote_checking_service
      genv
      env
      schedule_env.num_remote_workers
      schedule_env.batch_size
  in
  (env, genv, delegate_state)

(* Parse input_file which should contain a list of php files relative to root *)
let read_input_file input_file =
  let file_content = Disk.cat input_file in
  let file_lines = String.split_on_char '\n' (String.trim file_content) in
  List.map (fun x -> Relative_path.from_root x) file_lines

let print_errors errors =
  let print_error l =
    Hh_logger.log "%s" (Errors.to_string (Errors.to_absolute_for_test l))
  in
  List.iter print_error errors;
  ()

(*
  Schedule type checking for input file. 
  The type checking mode can be controlled by --num-remote-workers/--num-remote-workers options:
    If --num-remote-workers != 0, remote type checking will be enabled.
      Otherwise, pure-local type checking is used.
    If --num-remote-workers !=0 and --num-locak-workers == 0, pure-remote
      remote type checking will be used.
*)
let schedule_type_checking schedule_env =
  let (env, genv, delegate_state) = create_service_delegate schedule_env in
  let telemetry = Telemetry.create () in
  let memory_cap =
    genv.ServerEnv.local_config
      .ServerLocalConfig.max_typechecker_worker_memory_mb
  in
  let files_to_check = read_input_file schedule_env.input_file in
  let check_info =
    Typing_check_service.
      {
        (ServerCheckUtils.get_check_info genv env) with
        profile_log = true;
        profile_type_check_duration_threshold = 0.0;
      }
  in
  let ctx = Provider_utils.ctx_from_server_env env in
  (* Typing checking entry point *)
  let (res, _delegate_state, _telemetry) =
    Typing_check_service.go
      ctx
      genv.workers
      delegate_state
      telemetry
      Relative_path.Set.empty
      files_to_check
      ~memory_cap
      ~check_info
  in
  let errs = Errors.get_error_list res in
  match List.length errs with
  | 0 -> Hh_logger.log "Type check finished with zero error."
  | _ -> print_errors errs

let () =
  let () = Daemon.check_entry_point () in
  let command = parse_args () in
  let _errors =
    match command with
    | CSchedule schedule_env -> schedule_type_checking schedule_env
    | CWork work_env ->
      (* TODO: RemoteWorker.go work_env *)
      ignore work_env
  in
  Exit_status.exit Exit_status.No_error
