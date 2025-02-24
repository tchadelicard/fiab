# FIAB - reliable distributed systems project

## Overview

This project was developed as part of the **FIAB** course, which focuses on the reliability of distributed systems. The implementation was done in **Elixir**, leveraging its concurrency and fault-tolerance features to build a scalable and robust architecture. Over multiple phases, we progressively improved the system from simple experimentation with Elixir to a fully distributed, fault-tolerant architecture with load balancing, consistent hashing, and replica management.

## Key principles implemented

Each phase of the project introduced new reliability and scalability mechanisms:

### **hw_1 & hw_2: getting started with Elixir**
- Learning Elixir syntax and functional programming paradigms.
- Implementing simple components such as a lexer, parser, evaluator, and an alarm system using **GenServer**.

### **hw_3: introduction to fault-tolerant state management**
- First **GenServer-based** implementation of a statistics management service.
- Handling in-memory data and periodic state persistence.

### **hw_4: enhancing reliability with supervision and persistence**
- Introduced **DynamicSupervision** to manage independent transactors.
- Implemented periodic state saving to ensure data consistency.
- Added **non-blocking file scanning** for processing product statistics.

### **hw_5: distributed order processing**
- Introduced a **fully distributed architecture** with multiple nodes.
- Implemented **OrderTransactor** GenServers that process orders sequentially.
- Added **exponential backoff for retries** to improve error resilience.
- Developed a **load-aware dispatcher** for balancing transactors across nodes.

### **hw_6: fully distributed system with load balancing**
- Implemented **consistent hashing** using `libring` for scalable node assignment.
- Introduced a **round-robin load balancer** to distribute HTTP requests evenly.
- Enhanced **replica management** with leader election and failover mechanisms.
- Optimized transactor lifecycle with timeout-based shutdown to free resources.
- Implemented **node monitoring** to detect failures and redistribute work dynamically.

## Proposed improvements

### 1. **dynamic node discovery**
- Implement a **discovery service** for nodes to register upon joining.
- Allows dynamic scaling without manual reconfiguration.

### 2. **load balancer health awareness**
- Add **health checks** to avoid routing to failing nodes.
- Improve request distribution based on node performance.

### 3. **enhanced transactor fault tolerance**
- Implement **checkpointing** to periodically save state.
- Ensures seamless recovery from failures.

### 4. **handling network partitions**
- Add **partition-aware leader election** to maintain consistency.
- Ensures continued operation during network splits.

## Conclusion

Through this project, we explored key concepts in **reliable distributed system design** using **Elixir**. The transition from simple Elixir experimentation to a fully distributed architecture with **fault tolerance, load balancing, and replica management** demonstrates the principles of **FIAB** and the importance of **scalable, resilient systems** in real-world applications.

---

**Course:** FIAB - reliability of distributed systems  
**Language:** Elixir  
**Key technologies:** GenServer, supervisor trees, distributed hashing, load balancing, fault tolerance
