#!/bin/bash

cons_svr="node-4"
dur_svrs=("node-1" "node-2" "node-3")
shard_0=("node-5" "node-6")
client_node="node-0"
username="sgbhat3"

pe="/users/$username/.ssh/id_rsa"
data_dir="/users/$username/data"
log_dir="$data_dir/logs"
ll_dir="/proj/rasl-PG0/$username/LazyLog"

# arg: ip_addr of node, number of threads
dur_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/dur_log/dursvr -P cfg/durlog.prop -P cfg/rdma.prop -p dur_log.server_uri=$1:31850 -p threadcount=$2"
}

cons_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/conssvr -P cfg/conslog.prop -P cfg/rdma.prop -P cfg/be.prop"
}

# arg: thread count
shard_cmd_primary() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/shardsvr -P cfg/shard0.prop -P cfg/rdma.prop -p threadcount=$1 -p leader=true"
}

# arg: ip_addr of node
shard_cmd_backup() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/shardsvr -P cfg/shard0.prop -P cfg/rdma.prop -p shard.server_uri=$1:31860"
}

# args: batch size, round
basic_be_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/basic_be -P cfg/be.prop -P cfg/rdma.prop -p batch=$1 -p round=$2"
}

basic_be_read_cmd() {
    echo "sudo GLOG_minloglevel=1 ../build/src/cons_log/storage/basic_be_read -P ../cfg/be.prop -P ../cfg/rdma.prop -p batch=$2 -p round=$3 -p threadcount=$1"
}

# args: requests, runtime in secs, threads 
read_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/client/benchmarking/read_bench -P cfg/rdma.prop -P cfg/client.prop -P cfg/be.prop -p request_count=$1 -p runtime_secs=$2 -p threadcount=$3"
}

# args: runtime in secs, threads 
mixed_cmd() {
    echo "sudo GLOG_minloglevel=1 ../build/src/client/benchmarking/mixed_bench -P ../cfg/rdma.prop -P ../cfg/client.prop -P ../cfg/be.prop -p runtime_secs=$1 -p threadcount=$2"
}

dur_svrs_ip=()
backup_ip=""

# arg: node to ssh into
get_ip() {
    ip=$(ssh -o StrictHostKeyChecking=no -i $pe $username@$1 "ifconfig | grep 'netmask 255.255.255.0'")
    ip=$(echo $ip | awk '{print $2}')
    echo $ip
}

# arg: number of threads
run_dur_svrs() {
    local primary_done=false
    for svr in "${dur_svrs[@]}"; 
    do 
        if ${primary_done}; then 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(dur_cmd $(get_ip $svr) $1) > $log_dir/dursvr_$svr.log 2>&1 &\""
        else 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(dur_cmd $(get_ip $svr) $1) -p leader=true > $log_dir/dursvr_$svr.log 2>&1 &\""
            primary_done=true
        fi 
    done 
}

run_cons_svr() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "sh -c \"cd $ll_dir && nohup $(cons_cmd) > $log_dir/conssvr_$svr.log 2>&1 &\""
}

# arg: read thread count
run_shard_svr() {
    local primary_done=false
    for svr in "${shard_0[@]}"; 
    do 
        if ${primary_done}; then 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(shard_cmd_backup $(get_ip $svr)) > $log_dir/shardsvr_$svr.log 2>&1 &\""
        else 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(shard_cmd_primary $1) > $log_dir/shardsvr_$svr.log 2>&1 &\""
            primary_done=true
        fi 
    done 
}

# args: batch_size, rounds
load_keys() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(basic_be_cmd $1 $2) > $log_dir/basic_be_$client_node.log 2>&1\"" &
    wait
}

# args: num request, time to run, num threads
run_read_bench() {
    # local half=$(($3/2))
    local half=$3
    if (($3 % 2 == 0)); then 
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node):31851 -p shard.client_uri=$(get_ip $client_node):31860 > $log_dir/read_bench_$client_node.log 2>&1\"" &
        # ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node_1):31851 -p shard.client_uri=$(get_ip $client_node_1):31860 > $log_dir/read_bench_$client_node_1.log 2>&1\"" &
    else
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node):31851 -p shard.client_uri=$(get_ip $client_node):31860 > $log_dir/read_bench_$client_node.log 2>&1\"" &
        # ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $(($half + 1))) -p dur_log.client_uri=$(get_ip $client_node_1):31851 -p shard.client_uri=$(get_ip $client_node_1):31860 > $log_dir/read_bench_$client_node_1.log 2>&1\"" &
    fi 
    wait
}

kill_shard_svrs() {
    for svr in "${shard_0[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo pkill -2 shardsvr; sudo pkill -9 shardsvr"
    done 
}

kill_dur_svrs() {
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo pkill -2 dursvr; sudo pkill -9 dursvr"
    done 
}

kill_cons_svr() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "sudo pkill -2 conssvr; sudo pkill -9 conssvr"
}

kill_clients() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sudo pkill -9 basic_be" 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sudo pkill -9 read_bench"
    # ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sudo pkill -9 basic_be" 
    # ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sudo pkill -9 read_bench"
}

drop_shard_caches() {
    for svr in "${shard_0[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
    done 
}

collect_logs() {
    for svr in "${shard_0[@]}"; 
    do
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$svr:$log_dir/*" "$ll_dir/logs/"
    done 
    scp -o StrictHostKeyChecking=no -i $pe -r "$username@$cons_svr:$log_dir/*" "$ll_dir/logs/"
    for svr in "${dur_svrs[@]}"; 
    do
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$svr:$log_dir/*" "$ll_dir/logs/"
    done 
    scp -o StrictHostKeyChecking=no -i $pe -r "$username@$client_node:$log_dir/*" "$ll_dir/logs/"
    # scp -o StrictHostKeyChecking=no -i $pe -r "$username@$client_node_1:$log_dir/*" "$ll_dir/logs/"

}

clear_nodes() {
    for svr in "${shard_0[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo rm -rf $data_dir/*"
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "sudo rm -rf $data_dir/*"
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo rm -rf $data_dir/*"
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sudo rm -rf $data_dir/*"
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sudo rm -rf $data_dir/*"
}

setup_data() {
    clear_nodes
    for svr in "${shard_0[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "mkdir $log_dir"
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "mkdir $log_dir"
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "mkdir $log_dir"
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "mkdir $log_dir"
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "mkdir $log_dir"
}

# mode 
#   0 -> run expt
#   

mode="$1"
clients=("1" "2" "4" "6" "8" "9" "10" "12" "14" "16" "18")
if [ "$mode" -eq 0 ]; then # run expt   
    for clients in "${clients[@]}";
    do 
        echo "Running for $clients clients"
        kill_shard_svrs
        kill_cons_svr
        kill_dur_svrs
        kill_clients

        run_shard_svr $clients
        run_dur_svrs $clients
        run_cons_svr

        drop_shard_caches
        run_read_bench 10000000 180 $clients
        kill_shard_svrs
        kill_dur_svrs
        kill_cons_svr
        collect_logs
        sudo mkdir ${ll_dir}/logs_$clients
        sudo mv $ll_dir/logs/* ${ll_dir}/logs_$clients
    done 
elif [ "$mode" -eq 1 ]; then # load 10 million keys
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients

    setup_data
    run_shard_svr 1
    run_dur_svrs 1
    run_cons_svr

    # load 10 million keys
    load_keys 10000 1000
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs

    collect_logs
elif [ "$mode" -eq 2 ]; then
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients

    setup_data
    run_shard_svr $2
    run_dur_svrs $2
    run_cons_svr

    echo $2 $3 $4
    $(basic_be_read_cmd $2 $3 $4)
elif [ "$mode" -eq 3 ]; then
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients

    setup_data
    run_shard_svr $2
    run_dur_svrs $2
    run_cons_svr

    echo $3 $4
    $(mixed_cmd $3 $4)
else
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients
    collect_logs
fi