require 'dbi'
require 'yaml'

DEFAULT_JOB_ARGS = {
  :queue => "default",
  :walltime => 7200,
  :res => "resource_id=1",
  :propreties => "",
  :type => nil
}

def oar_load_test_config
  puts "### Reading configuration oar_test_conf file..." 
  $conf = YAML::load(IO::read('oar_test.conf'))
  $db_type = $conf['DB_TYPE']
  puts "DB TYPE: #{$conf['DB_TYPE']}"
end

def oar_db_connect
	if $db_type == "mysql"
		$db_type == "Mysql"
	end
	$dbh = DBI.connect("dbi:#{$db_type}:#{$conf['DB_BASE_NAME']}:#{$conf['DB_HOSTNAME']}",
										 "#{$conf['DB_BASE_LOGIN_RO']}","#{$conf['DB_BASE_PASSWD_RO']}")
  puts "DB Connection Establised"
end

def oar_db_disconnect
  $dbh.disconnect
end

def get_last_insert_id(seq)
  id = 0
  if ($db_type == "Mysql" || $db_type == "mysql" )
    id=$dbh.select_one("SELECT LAST_INSERT_ID()")[0]
  else
    id=$dbh.select_one("SELECT CURRVAL('#{seq}')")[0]
  end
  return id
end

#$jobs = DB[:jobs]
#$moldable = DB[:moldable_job_descriptions]
#$job_resource_groups = DB[:job_resource_groups]
#$job_resource_description = DB[:job_resource_descriptions]
#$job_types = DB[:job_types]
#$resources = DB[:resources]

def oar_job_insert(j_args={})
  args = {}
  DEFAULT_JOB_ARGS.each do |k,v|
    if j_args[k].nil?
      args[k]=v
    else
      args[k]=j_args[k]
    end
  end
  sth = $dbh.execute("insert into jobs (job_name,state,queue_name,properties,launching_directory,checkpoint_signal) values 
                                      ('yop','Waiting','#{args[:queue]}','#{args[:properties]}','yop',0)")
  sth.finish

  job_id= get_last_insert_id('jobs_job_id_seq') 

  #moldable_id = $moldable.insert(:moldable_job_id => job_id, :moldable_walltime => walltime)
  $dbh.execute("insert into moldable_job_descriptions (moldable_job_id,moldable_walltime) values (#{job_id},#{args[:walltime]})").finish 
  moldable_id = get_last_insert_id('moldable_job_descriptions_moldable_id_seq')

  args[:res].split("+").each do |r|
    #res_group_id =	$job_resource_groups.insert(:res_group_moldable_id => moldable_id, :res_group_property => 'type = "default"')
    $dbh.execute("insert into job_resource_groups (res_group_moldable_id,res_group_property) values 
                                                  (#{moldable_id},'type = ''default''')").finish
    res_group_id = get_last_insert_id('job_resource_groups_res_group_id_seq')

    r.split('/').each_with_index do |type_value,order|
      type,value = type_value.split('=')
      #$job_resource_description.insert(:res_job_group_id => res_group_id.to_i, :res_job_resource_type => type, :res_job_value => value.to_i, :res_job_order => order.to_i)
      $dbh.execute("insert into job_resource_descriptions (res_job_group_id, res_job_resource_type, res_job_value, res_job_order ) 
                   values (#{res_group_id.to_i},'#{type}',#{value.to_i},#{order.to_i})").finish
    end  
  end

  #job's types insertion
  if !args[:types].nil?
    !args[:types].split(',').each do |type|
#      $job_types.insert(:job_id => job_id, :type => type)
      $dbh.execute("insert into job_types (job_id, type) values (#{job_id},'#{type}')").finish
    end
  end

  return job_id
end


def multiple_requests_execute(reqs)
  #Strange dbi_mysql doesn't accept multiple request in one dbh.execute ???
  reqs.split(';').each do |r|
    if (r =~ /\w/)
      $dbh.execute(r).finish
    end
  end
end

def oar_truncate_jobs
#  DB << "
 requests = "
    TRUNCATE accounting;
    TRUNCATE assigned_resources;
    TRUNCATE challenges;
    TRUNCATE event_logs;
    TRUNCATE event_log_hostnames;
    TRUNCATE files;
    TRUNCATE frag_jobs;
    TRUNCATE gantt_jobs_predictions;
    TRUNCATE gantt_jobs_predictions_log;
    TRUNCATE gantt_jobs_predictions_visu;
    TRUNCATE gantt_jobs_resources;
    TRUNCATE gantt_jobs_resources_log;
    TRUNCATE gantt_jobs_resources_visu;
    TRUNCATE jobs;
    TRUNCATE job_dependencies;
    TRUNCATE job_resource_descriptions;
    TRUNCATE job_resource_groups;
    TRUNCATE job_state_logs;
    TRUNCATE job_types;
    TRUNCATE moldable_job_descriptions;
    TRUNCATE resource_logs;
"
  multiple_requests_execute(requests)
end

def oar_update_visu
  requests = "
    DELETE FROM gantt_jobs_predictions_visu;
    DELETE FROM gantt_jobs_resources_visu;
    INSERT INTO gantt_jobs_predictions_visu SELECT * FROM gantt_jobs_predictions;
    INSERT INTO gantt_jobs_resources_visu SELECT * FROM gantt_jobs_resources;
  "
  multiple_requests_execute(requests)
end


#def oar_sql_file file_name
#  DB << File.open(file_name, "r").read
#end

def oar_resource_insert(args={})i

  if (args.nil?)
    $dbh.execute("insert into resources (state) values ('Alive')").finish
  else
    if !args[:nb_resources].nil?
      args[:nb_resources].times do
         $dbh.execute("insert into resources (state) values ('Alive')").finish   
      end
    end
  end
end

def oar_truncate_resources
#  DB << "
  requests = "
    TRUNCATE resources;
    TRUNCATE resource_logs;
    "
  multiple_requests_execute(requests)
end

def oar_db_clean
  oar_truncate_jobs
  oar_truncate_resources
end

if ($0=='irb')
  puts 'irb session detected, db connection launched'
  oar_load_test_config
  oar_db_connect
end
# 50.times do |i| oar_job_insert(:res=>"resource_id=#{i}",:walltime=> 300) end
