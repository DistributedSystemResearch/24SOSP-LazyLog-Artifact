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














