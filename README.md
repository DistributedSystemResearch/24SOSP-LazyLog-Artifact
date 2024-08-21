# LazyLog: A New Shared Log Abstraction for Low-Latency Applications 
This repo is the artifact for: <to be added>

## Setup
For ease of setup, we request that the source code for LazyLog and eRPC and their binaries be hosted on a network-file system so that all the nodes can share these files. 
Some of the installation steps need to be done on all the nodes (16 is sufficient for Erwin-blackbox) and some such as the compilation need only be done on one node. The scripts expect that the data directory on all the nodes to store the run-time logs as well as the storage for the shared-log be mounted at `/data` on each node. **For the benefit of the reviewers, we will provide a cluster which already has all the following setup steps completed**. 

### Installation to be done on all the nodes
* Install RDMA drivers
```
cd scripts
./install_mlnx.sh
```
This needs to be done on all the nodes in the cluster and the nodes must be rebooted after this step completes
* Install dependencies
```
cd scripts
./deps.sh
```
* Configure huge-pages
```
echo 2048 | sudo tee /proc/sys/vm/nr_hugepages
```
* Own the data directory
```
sudo chown -R <username> /data
```

### Installation to be done on any one node
The following steps assume that the network file-system is at `/sharedfs`
* Get and install eRPC 
```
cd /sharedfs
git clone https://github.com/erpc-io/eRPC
git checkout 793b2a93591d372519983fe23ea4e438199f2462
cmake . -DPERF=ON -DTRANSPORT=infiniband -DROCE=ON -DLOG_LEVEL=info
make -j
```
* Get and install LazyLog
```
cd /sharedfs
git clone https://github.com/dassl-uiuc/LazyLog-Artifact.git --recursive
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```
## Running a simple append-only benchmark on the provided cluster
* Login into `node0` in the cluster we provide. The eRPC and LazyLog directories will be in the shared NFS folder at `/proj/rasl-PG0/LL-AE`. 
* Modify your username and passless private key path in `scripts/run.sh`. 
* Run the following 
```
cd scripts
./run.sh 2
```
* The script setups up the various Erwin-blackbox components (such as the shard servers and sequencing layer servers) and starts an append-only benchmark on Erwin-blackbox with 5 backend shards, 4 client threads spread over 2 client nodes (`node0` and `node15`) and 4K sized messages. The benchmark should run for approximately 2 minutes and terminate. On termination, in the root directory of LazyLog, a folder with the name `logs_<num_client>_<message_size>_<num_shards>` is created which contains the runtime log file with the latency and throughput metrics. 
* We provide an analysis script to display the standard metrics in a human readable form which can be invoked as 
```
cd scripts
python3 analyze.py
```
* If you wish the change the number of clients and message size, they can be modified in lines 275-280 in the `run.sh` script. 


## Supported Platforms
The two lazylog systems Erwin-blackbox and Erwin-st have been tested on the following platforms
* OS: Ubuntu 22.04 LTS
* NIC: Mellanox MT27710 Family ConnectX-4 Lx (25Gb RoCE)
* RDMA Driver: MLNX_OFED-23.10-0.5.5.0









