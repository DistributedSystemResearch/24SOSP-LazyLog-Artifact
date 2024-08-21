#!/bin/bash

set -x 
cons_svr="node4"
dur_svrs=("node1" "node2" "node3")
threeway="false"
scalable_tput="false"
if [ "$scalable_tput" = "true" ]; then 
    shard_pri=("node5" "node7" "node9" "node11" "node13" "node15" "node17" "node19" "node21" "node23")
    shard_bac=("node6" "node8" "node10" "node12" "node14" "node16" "node18" "node20" "node22" "node24")
elif [ "$threeway" = "true" ]; then 
    shard_pri=("node5" "node7" "node9" "node11" "node13")
    shard_bac=("node6" "node8" "node10" "node12" "node14")
    shard_bac1=("node14" "node12" "node8" "node10" "node6")
else 
    shard_pri=("node5" "node7" "node9" "node11" "node13")
    shard_bac=("node6" "node8" "node10" "node12" "node14")
fi
client_nodes=("node0" "node15")
username="<your_username>"

pe="/users/$username/.ssh/id_rsa"
data_dir="/data"
log_dir="$data_dir/logs"
ll_dir="/proj/rasl-PG0/LL-AE/LazyLog-Artifact"

# arg: ip_addr of node, number of threads
dur_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/dur_log/dursvr -P cfg/durlog.prop -P cfg/rdma.prop -p dur_log.server_uri=$1:31850"
}

cons_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/conssvr -P cfg/conslog.prop -P cfg/rdma.prop -P cfg/be.prop -P cfg/dl_client.prop"
}

shard_cmd_primary() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/shardsvr -P cfg/rdma.prop -P cfg/be.prop -P cfg/shard$1.prop -p leader=true"
}

# arg: ip_addr of node
shard_cmd_backup() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/shardsvr -P cfg/rdma.prop -P cfg/be.prop -P cfg/shard$2.prop -p shard.server_uri=$1:31860"
}

# used when running two shard servers on the same ip. 
# must use 31861 port
# arg: ip_addr of node
shard_cmd_backup_prime() {
    echo "sudo GLOG_minloglevel=1 ./build/src/cons_log/storage/shardsvr -P cfg/rdma.prop -P cfg/be.prop -P cfg/shard$2.prop -p shard.server_uri=$1:31861"
}

# args: batch size, round
basic_be_cmd() {
    echo "sudo ./build/src/cons_log/storage/basic_be -P cfg/be.prop -P cfg/rdma.prop -p batch=$1 -p round=$2"
}

basic_be_read_cmd() {
    echo "sudo ../build/src/cons_log/storage/basic_be_read -P ../cfg/be.prop -P ../cfg/rdma.prop -p batch=$2 -p round=$3 -p threadcount=$1"
}

# args: requests, runtime in secs, threads 
read_cmd() {
    echo "sudo ./build/src/client/benchmarking/read_bench -P cfg/rdma.prop -P cfg/dl_client.prop -P cfg/be.prop -p request_count=$1 -p runtime_secs=$2 -p threadcount=$3"
}

# args: runtime in secs, threads 
mixed_cmd() {
    echo "sudo ../build/src/client/benchmarking/mixed_bench -P ../cfg/rdma.prop -P ../cfg/dl_client.prop -P ../cfg/be.prop -p runtime_secs=$1 -p threadcount=$2"
}

# args: runtime in secs, number of threads, request size
append_cmd() {
    echo "sudo GLOG_minloglevel=1 ./build/src/client/benchmarking/append_bench -P cfg/be.prop -P cfg/dl_client.prop -P cfg/rdma.prop -p runtime_secs=$1 -p threadcount=$2 -p request_size_bytes=$3"
}

dur_svrs_ip=()
backup_ip=""

# arg: node to ssh into
get_ip() {
    ip=$(ssh -o StrictHostKeyChecking=no -i $pe $username@$1 "ifconfig | grep 'netmask 255.255.255.0'")
    ip=$(echo $ip | awk '{print $2}')
    echo $ip
}

run_dur_svrs() {
    local primary_done=false
    for svr in "${dur_svrs[@]}"; 
    do 
        if ${primary_done}; then 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(dur_cmd $(get_ip $svr)) > $log_dir/dursvr_$svr.log 2>&1 &\""
        else 
            ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sh -c \"cd $ll_dir && nohup $(dur_cmd $(get_ip $svr)) -p leader=true > $log_dir/dursvr_$svr.log 2>&1 &\""
            primary_done=true
        fi 
    done 
}

run_cons_svr() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "sh -c \"cd $ll_dir && nohup $(cons_cmd) > $log_dir/conssvr_$svr.log 2>&1 &\""
}

# args: num shards
run_shard_svr() {
    for ((i=0; i<$1; i++)); 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@${shard_bac[$i]} "sh -c \"cd $ll_dir && nohup $(shard_cmd_backup $(get_ip ${shard_bac[$i]}) $i) > $log_dir/shardsvr_backup_$i_${shard_bac[$i]}.log 2>&1 &\""
    done 
    if [ "$threeway" = "true" ]; then 
        for ((i=0; i<$1; i++)); 
        do
            ssh -o StrictHostKeyChecking=no -i $pe $username@${shard_bac1[$i]} "sh -c \"cd $ll_dir && nohup $(shard_cmd_backup_prime $(get_ip ${shard_bac1[$i]}) $i) > $log_dir/shardsvr_backup1_$i_${shard_bac1[$i]}.log 2>&1 &\""
        done 
    fi
    sleep 2
    for ((i=0; i<$1; i++)); 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@${shard_pri[$i]} "sh -c \"cd $ll_dir && nohup $(shard_cmd_primary $i) > $log_dir/shardsvr_pri_$i_${shard_pri[$i]}.log 2>&1 &\""
    done 
    sleep 2
}

# args: batch_size, rounds
load_keys() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(basic_be_cmd $1 $2) > $log_dir/basic_be_$client_node.log 2>&1\"" &
    wait
}

# args: num request, time to run, num threads
run_read_bench() {
    local half=$(($3/2))
    if (($3 % 2 == 0)); then 
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node):31851 -p shard.client_uri=$(get_ip $client_node):31860 > $log_dir/read_bench_$client_node.log 2>&1\"" &
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node_1):31851 -p shard.client_uri=$(get_ip $client_node_1):31860 > $log_dir/read_bench_$client_node_1.log 2>&1\"" &
    else
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $half) -p dur_log.client_uri=$(get_ip $client_node):31851 -p shard.client_uri=$(get_ip $client_node):31860 > $log_dir/read_bench_$client_node.log 2>&1\"" &
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client_node_1 "sh -c \"cd $ll_dir && nohup $(read_cmd $1 $2 $(($half + 1))) -p dur_log.client_uri=$(get_ip $client_node_1):31851 -p shard.client_uri=$(get_ip $client_node_1):31860 > $log_dir/read_bench_$client_node_1.log 2>&1\"" &
    fi 
    wait
}

# args: num shards
change_num_shards() {
    sed -i "s/shard\.num=.*/shard.num=${1}/g" $ll_dir/cfg/be.prop
}

# args: runtime in secs, number of threads, request size
run_append_bench() {
    local num_client_nodes=${#client_nodes[@]}
    local low_num=$(($2 / $num_client_nodes))
    local mod=$(($2 % $num_client_nodes))

    for ((i=0; i<num_client_nodes; i++));
    do
        local client="${client_nodes[$i]}"
        if [ "$i" -lt "$mod" ]; then
            # If there's a remainder, assign one additional job to the first 'mod' clients
            num_jobs_for_client=$((low_num + 1))
        else
            num_jobs_for_client=$low_num
        fi
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client "sh -c \"cd $ll_dir && nohup $(append_cmd $1 $num_jobs_for_client $3) -p dur_log.client_uri=$(get_ip $client):31851 -p node_id=$i > $log_dir/append_bench_$client.log 2>&1\"" &
    done
    wait
}

kill_shard_svrs() {
    for svr in "${shard_pri[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo bash -s shardsvr" < kill_process.sh &
    done
    for svr in "${shard_bac[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo bash -s shardsvr" < kill_process.sh &
    done 
    wait
}

kill_dur_svrs() {
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo bash -s dursvr" < kill_process.sh &
    done 
    wait
}

kill_cons_svr() {
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "pid=\$(sudo lsof -i :31852 | awk 'NR==2 {print \$2}') ; sudo kill -2 \$pid 2> /dev/null || true" 
}

kill_clients() {
    for client in "${client_nodes[@]}"; 
    do     
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client "sudo bash -s append_bench" < kill_process.sh &
    done 
    wait
}

drop_shard_caches() {
    for svr in "${shard_pri[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"" 
    done 
    for svr in "${shard_bac[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
    done 
}

collect_logs() {
    for svr in "${shard_pri[@]}"; 
    do
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$svr:$log_dir/*" "$ll_dir/logs/"
    done
    for svr in "${shard_bac[@]}"; 
    do
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$svr:$log_dir/*" "$ll_dir/logs/"
    done
    scp -o StrictHostKeyChecking=no -i $pe -r "$username@$cons_svr:$log_dir/*" "$ll_dir/logs/"
    for svr in "${dur_svrs[@]}"; 
    do
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$svr:$log_dir/*" "$ll_dir/logs/"
    done 
    for client in "${client_nodes[@]}"; 
    do  
        scp -o StrictHostKeyChecking=no -i $pe -r "$username@$client:$log_dir/*" "$ll_dir/logs/"
    done
}

clear_nodes() {
    for svr in "${shard_pri[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo rm -rf $data_dir/*" &
    done 
    for svr in "${shard_bac[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo rm -rf $data_dir/*" &
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "sudo rm -rf $data_dir/*" &
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "sudo rm -rf $data_dir/*" &
    done 
    for client in "${client_nodes[@]}"; 
    do 
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client "sudo rm -rf $data_dir/*" &
    done
    wait
}

setup_data() {
    clear_nodes
    for svr in "${shard_pri[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "mkdir $log_dir"
    done 
    for svr in "${shard_bac[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "mkdir $log_dir"
    done 
    ssh -o StrictHostKeyChecking=no -i $pe $username@$cons_svr "mkdir $log_dir"
    for svr in "${dur_svrs[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$svr "mkdir $log_dir"
    done 
    for client in "${client_nodes[@]}"; 
    do
        ssh -o StrictHostKeyChecking=no -i $pe $username@$client "mkdir $log_dir"
    done 
}

# mode 
#   0 -> run expt
#   

mode="$1"
clients=("4")
num_shards=("5")
msg_size=("4096")
if [ "$mode" -eq 0 ]; then # run expt   
    for clients in "${clients[@]}";
    do 
        echo "Running for $clients clients"
        kill_shard_svrs
        kill_cons_svr
        kill_dur_svrs
        kill_clients

        run_shard_svr
        run_dur_svrs
        run_cons_svr

        drop_shard_caches
        run_read_bench 10000000 180 $clients
        kill_shard_svrs
        kill_dur_svrs
        kill_cons_svr
        collect_logs
        mkdir ${ll_dir}/logs_$clients
        mv $ll_dir/logs/* ${ll_dir}/logs_$clients
    done 
elif [ "$mode" -eq 1 ]; then # load 10 million keys
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients

    setup_data
    run_shard_svr
    run_dur_svrs
    run_cons_svr

    # load 10 million keys
    load_keys 10000 1000
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs

    collect_logs
elif [ "$mode" -eq 2 ]; then
    for size in "${msg_size[@]}"; 
    do 
        for shard in "${num_shards[@]}";
        do 
            for c in "${clients[@]}";
            do 
                echo "Running for $c clients, $size msg size, $shard shards"
                kill_cons_svr
                kill_shard_svrs
                kill_dur_svrs
                kill_clients

                setup_data
                change_num_shards $shard
                run_shard_svr $shard
                run_dur_svrs
                run_cons_svr

                run_append_bench 120 $c $size
                kill_cons_svr
                kill_shard_svrs
                kill_dur_svrs
                collect_logs
                mkdir ${ll_dir}/logs_${c}_${size}_${shard}
                mv $ll_dir/logs/* ${ll_dir}/logs_${c}_${size}_${shard}
            done 
        done
    done 
elif [ "$mode" -eq 3 ]; then
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients

    setup_data
    run_shard_svr
    run_dur_svrs
    run_cons_svr

    echo $3 $4
    $(mixed_cmd $3 $4)
elif [ "$mode" -eq 4 ]; then 
    kill_cons_svr
    kill_dur_svrs
    kill_shard_svrs

    setup_data
    run_shard_svr 1
    run_dur_svrs
    run_cons_svr
else 
    kill_shard_svrs
    kill_cons_svr
    kill_dur_svrs
    kill_clients
    collect_logs
fi