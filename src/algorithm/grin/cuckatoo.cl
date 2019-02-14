#include "siphash.h"

#define FOREACH_PARALLEL(cmd, i, n) \
    for(uint32_t i = get_local_id(0); i < (n); i += get_local_size(0)) { \
         cmd; \
    } \


__kernel void FillBuffer(
        __global uint32_t* buffer,
        const uint32_t pattern,
        const uint32_t blocksize
) 
{
    uint32_t offset = get_group_id(0) * blocksize;
    buffer += offset;
    
    FOREACH_PARALLEL(buffer[i] = pattern, i, blocksize);
}


typedef uint32_t Bitmap;

void addToNodes(
        uint32_t node, 
        __global uint32_t* nodes, 
        __global uint32_t* bucketCounters, 
        uint32_t maxBucketSize) 
{
    uint32_t bucket = (node >> BUCKET_BIT_SHIFT);
    uint32_t pos = atomic_inc(&bucketCounters[bucket]);
    //uint32_t pos = bucketCounters[bucket]++;
    if (pos >= maxBucketSize) {
        return;
    }
    nodes[maxBucketSize * bucket + pos] = node;
}

void addToNodesL(
        uint32_t node, 
        __local uint32_t* nodes, 
        __local uint32_t* bucketCounters, 
        uint32_t maxBucketSize) 
{
    uint32_t bucket = (node >> BUCKET_BIT_SHIFT);
    uint32_t pos = atomic_inc(&bucketCounters[bucket]);
    if (pos >= maxBucketSize) {
        return;
    }
    nodes[maxBucketSize * bucket + pos] = node;
}


bool isActive(const __global Bitmap* bitmap, uint32_t node) {
    uint32_t partner = node >> 1;
    return (bitmap[partner/32] & (1 << (partner % 32))) != 0; 
}

__kernel void CreateNodes(
    const struct SiphashKeys keys,
    __global const Bitmap* activeEdges,
    const uint32_t uorv, // TODO remove
    const uint32_t nodeMask,
    __global uint32_t* nodes,
    __global uint32_t* bucketCounters,
    const uint32_t maxBucketSize)
{
    // Every thread processes one word of input (32 bits).
    // TODO compact input node set to reduce hash count in non-first round
    
    const uint32_t buffers = 1 << (31 - BUCKET_BIT_SHIFT);
    const uint32_t bsize = 120;
    
    __local uint32_t buf[buffers * bsize];
    __local uint32_t cnt[buffers];
    
    FOREACH_PARALLEL(cnt[i] = 0, i, buffers);
    barrier(CLK_LOCAL_MEM_FENCE);

    uint32_t bits = activeEdges[get_global_id(0)];
    for(int i=0; i<32; ++i) {
        if ((bits >> i & 1) == 0) {
            continue;
        }
        
        uint32_t nodeIn = 32 * (uint64_t)get_global_id(0) + i;
        uint32_t nonce = 2 * nodeIn + uorv;
        uint32_t nodeOut = siphash24(keys, nonce) & nodeMask;

        addToNodes(nodeOut, nodes, bucketCounters, maxBucketSize);
        //addToNodesL(nodeOut, buf, cnt, bsize);
    }
//    __local uint32_t m;
//    m = 0;
//    barrier(CLK_LOCAL_MEM_FENCE);
//    
//    __local uint32_t pos[buffers];
//    FOREACH_PARALLEL({
//        cnt[i] = min(bsize, cnt[i]);
//        pos[i] = atomic_add(&bucketCounters[i], cnt[i]);
//        m = atomic_max(&m, cnt[i]);
//    }, i, buffers);
//    barrier(CLK_LOCAL_MEM_FENCE);

//    FOREACH_PARALLEL({
//        int c = cnt[i];
//        __global uint32_t* n = &nodes[maxBucketSize * i + pos[i]];
//        for(int j=0; j<c; j += 4) {
//            *(__global uint4*)(&n[j]) = *(__local uint4*)(&buf[bsize * i + j]);
//        }
//    }, i, buffers);
    
//    for(int b = 0; b < buffers; ++b) {
//        __global uint32_t* n = &nodes[maxBucketSize * b + pos[b]];
//        FOREACH_PARALLEL(
//                //n[i] = buf[bsize * b + i],
//                *(__global uint4*)(&n[4*i]) = *(__local uint4*)(&buf[bsize * b + 4*i]),
//                i, cnt[i] / 4);
//    }
//    for(int b = 0; b < buffers; ++b) {
//        __global uint32_t* n = &nodes[maxBucketSize * b + pos[b]];        
//        async_work_group_copy(n, &buf[bsize * b], cnt[b], 0);
//    }
}


__attribute__((reqd_work_group_size(64, 1, 1)))
__kernel void KillEdgesAndCreateNodes(
    const struct SiphashKeys keys,
    const __global Bitmap* activeNodes,
    const uint32_t uorv,
    const uint32_t nodeMask,        
    __global Bitmap* activeEdges,
    __global uint32_t* nodes,
    __global uint32_t* bucketCounters,
    const uint32_t maxBucketSize)
{
    // Every thread processes one word of input (32 bits).
    __local uint32_t nonces[32 * 64];
    __local uint32_t pos;
    
    if (get_local_id(0) == 0) {
        pos = 0;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    
    uint32_t bits = activeEdges[get_global_id(0)];
    uint32_t rem = bits;
//    while(rem != 0) {
    for(int i=0; rem != 0; ++i) {
        int i = 31 - clz(rem);
        rem  ^= 1 << i;
        
//        if ((bits & (1 << i)) == 0) {
//            continue;
//        }
        
        uint32_t edge  = 32 * (uint64_t)get_global_id(0) + i;
        uint32_t nonce = 2 * edge | uorv;
        uint32_t nodeVorU = siphash24(keys, nonce ^ 1) & nodeMask;

        if (!isActive(activeNodes, nodeVorU)) {
            bits ^= (1 << i);
            continue;
        }
        
        uint32_t p = atomic_inc(&pos);
        nonces[p] = nonce;
    }
    activeEdges[get_global_id(0)] = bits;    
    barrier(CLK_LOCAL_MEM_FENCE);
    
    FOREACH_PARALLEL({
        uint32_t nodeUorV = siphash24(keys, nonces[i]) & nodeMask;
        addToNodes(nodeUorV, nodes, bucketCounters, maxBucketSize);
    }, i, pos);
}

    
__kernel void AccumulateNodes(
    __global const uint32_t* nodes,
    __global const uint32_t* bucketCounters,
    const uint32_t maxBucketSize,
    __global Bitmap* activeNodes,
    int initBitmap)
{
    const uint32_t localSize = 1 << BUCKET_BIT_SHIFT;
    //const uint32_t localSize = 1 << 17;
    __local Bitmap bitmap[localSize / 32];
    FOREACH_PARALLEL(bitmap[i] = 0, i, localSize / 32);
    barrier(CLK_LOCAL_MEM_FENCE);
    
    uint32_t bucket = get_group_id(0);
    uint32_t count = min(maxBucketSize, bucketCounters[bucket]);
    const __global uint32_t* myNodes = nodes + bucket * maxBucketSize;
//
//    FOREACH_PARALLEL({
//        uint32_t node = myNodes[i] % localSize;
//        atomic_or(&bitmap[node / 32], 1 << (node % 32));
//    }, i, count);
    
    FOREACH_PARALLEL({
        uint8 nodes = vload8(i, myNodes);
        atomic_or(&bitmap[(nodes.s0 % localSize) / 32], 1 << (nodes.s0 % 32));
        atomic_or(&bitmap[(nodes.s1 % localSize) / 32], 1 << (nodes.s1 % 32));
        atomic_or(&bitmap[(nodes.s2 % localSize) / 32], 1 << (nodes.s2 % 32));
        atomic_or(&bitmap[(nodes.s3 % localSize) / 32], 1 << (nodes.s3 % 32));
        atomic_or(&bitmap[(nodes.s4 % localSize) / 32], 1 << (nodes.s4 % 32));
        atomic_or(&bitmap[(nodes.s5 % localSize) / 32], 1 << (nodes.s5 % 32));
        atomic_or(&bitmap[(nodes.s6 % localSize) / 32], 1 << (nodes.s6 % 32));
        atomic_or(&bitmap[(nodes.s7 % localSize) / 32], 1 << (nodes.s7 % 32));
    }, i, count / 8);
    uint32_t i = (count / 8) * 8 + get_local_id(0);
    if (i < count) {
        uint32_t node = myNodes[i] % localSize;
        atomic_or(&bitmap[node / 32], 1 << (node % 32));
    }
    
    barrier(CLK_LOCAL_MEM_FENCE);
    
    __global uint32_t* myActiveNodes = activeNodes + bucket * (localSize / 32);
    if (initBitmap) {
        FOREACH_PARALLEL({
            myActiveNodes[i] = bitmap[i];
        }, i, localSize / 32);
    } else {
        FOREACH_PARALLEL({
            myActiveNodes[i] |= bitmap[i]; // TODO read-modify-write ... is there a better way?
        }, i, localSize / 32);
    }
}

__kernel void CombineActiveNodes(
        const __global Bitmap* activeNodesIn,
        __global Bitmap* activeNodesOut
)
{
    uint64_t in = ((const __global uint64_t*)activeNodesIn)[get_global_id(0)];
    uint32_t out = 0;
    for(int i=0; i<32; ++i) {
       int bit = (in >> (2*i)) & (in >> (2*i + 1)) & 1;
       out |= bit << i; 
    }
    activeNodesOut[get_global_id(0)] = out;
}

__kernel void KillEdges(
        const struct SiphashKeys keys,
        const __global Bitmap* activeNodes,
        const uint32_t uorv,
        const uint32_t nodeMask,        
        __global Bitmap* activeEdges
)
{
    // Every thread processes one word of input (32 bits).
    // TODO compact input node set to reduce hash count in non-first round

    uint32_t bits = activeEdges[get_global_id(0)];
    for(int i=0; i<32; ++i) {
        if ((bits >> i & 1) == 0) {
            continue;
        }
        
        uint32_t nodeIn = 32 * (uint64_t)get_global_id(0) + i;
        uint32_t nonce = 2 * nodeIn + uorv;
        uint32_t nodeOut = siphash24(keys, nonce) & nodeMask;

        if (!isActive(activeNodes, nodeOut)) {
            bits ^= (1 << i);
        }
    }
    activeEdges[get_global_id(0)] = bits;
}





