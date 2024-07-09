# Splunk Enterprise Migration Guide

This guide outlines the process for migrating a Splunk deployment from a distributed environment with 3 search heads in a cluster, 2 indexer clusters, 2 heavy forwarders, and 1 utility server to a new set of servers with the same architecture.

## Table of Contents

1. [Preparation](#1-preparation)
2. [Migrate Indexer Clusters](#2-migrate-indexer-clusters)
3. [Migrate Cluster Managers](#3-migrate-cluster-managers)
4. [Migrate Search Head Cluster](#4-migrate-search-head-cluster)
5. [Migrate Heavy Forwarders](#5-migrate-heavy-forwarders)
6. [Migrate Utility Server](#6-migrate-utility-server)
7. [Final Verification and Cutover](#7-final-verification-and-cutover)
8. [Decommission Old Environment](#8-decommission-old-environment)

## 1. Preparation

1. Document the current environment
2. Set up new servers with Splunk installed and basic configurations
3. Ensure network connectivity between old and new environments
4. Create a detailed migration schedule

## 2. Migrate Indexer Clusters

1. Add new indexers to the existing clusters:

   ```bash
   # For Splunk 8.1.0 and later
   sudo /opt/splunk/bin/splunk edit cluster-config -mode peer -manager_uri https://<existing_cluster_manager>:8089 -replication_port 9887 -secret <splunk_secret>

   # For versions before 8.1.0
   sudo /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://<existing_cluster_manager>:8089 -replication_port 9887 -secret <splunk_secret>

   sudo /opt/splunk/bin/splunk restart
   ```

2. Prepare to decommission old indexers:
   - Update forwarders to point to new indexers (adjust outputs.conf on the deployment server)
   - Put old indexers into detention:

   ```bash
   sudo /opt/splunk/bin/splunk edit cluster-config -auth <username>:<password> -manual_detention on
   ```

3. Decommission old indexers one at a time:

   ```bash
   sudo /opt/splunk/bin/splunk offline --enforce-counts
   ```

4. Wait for indexer status to show as "GracefulShutdown" in the Cluster Manager UI

5. Remove old peers from the cluster manager's list:

   ```bash
   sudo /opt/splunk/bin/splunk remove cluster-peers -peers <guid>,<guid>,...
   ```

6. Optimize data migration speed (optional):

   ```bash
   sudo /opt/splunk/bin/splunk edit cluster-config --max_peer_build_load 3 --max_peer_rep_load 6
   ```

## 3. Migrate Cluster Managers

1. Set up the new cluster manager:
   
   ```bash
   # Copy master-apps directory
   scp -r /opt/splunk/etc/master-apps/ splunk@<new_cm>:/opt/splunk/etc/

   # Copy server.conf
   scp /opt/splunk/etc/system/local/server.conf splunk@<new_cm>:/opt/splunk/etc/system/local/
   ```

2. On the new cluster manager, decrypt passwords:

   ```bash
   find /opt/splunk/etc -name '*.conf' -exec grep -inH '\$[0-9]\$' {} \;
   /opt/splunk/bin/splunk show-decrypted --value '$encryptedpassword'
   ```

3. Update server.conf on the new cluster manager with decrypted passwords

4. Back up the old cluster manager:

   ```bash
   tar -czvf splunkEtcBackup$(date +%Y%m%d).tgz /opt/splunk/etc
   ```

5. Stop Splunk on the old cluster manager:

   ```bash
   sudo /opt/splunk/bin/splunk stop
   ```

6. Copy the remote bundle to the new cluster manager:

   ```bash
   scp -r /opt/splunk/var/run/splunk/cluster/remote-bundle splunk@<new_cm>:/opt/splunk/var/run/splunk/cluster/remote-bundle
   ```

7. Start the new cluster manager:

   ```bash
   sudo /opt/splunk/bin/splunk restart
   ```

8. Update indexers to point to the new cluster manager:

   ```bash
   sudo /opt/splunk/bin/splunk edit cluster-config -mode peer -manager_uri https://<new_cm>:8089 -replication_port 9887 -secret <secret>
   ```

9. Update search heads to point to the new cluster manager:

   ```bash
   sudo /opt/splunk/bin/splunk edit cluster-config -mode searchhead -manager_uri https://<new_cm>:8089 -secret <your_key_decrypted>
   ```

## 4. Migrate Search Head Cluster

1. Set up new search head cluster:

   ```bash
   # On the new deployer
   sudo /opt/splunk/bin/splunk init shcluster-config -auth admin:changeme -mgmt_uri https://<new_deployer>:8089 -conf_deploy_fetch_url https://<new_deployer>:8089 -secret <your_secret> -shcluster_label <new_cluster_name>

   # On each new SH member
   sudo /opt/splunk/bin/splunk init shcluster-config -auth admin:changeme -mgmt_uri https://<new_member>:8089 -replication_port 9887 -secret <your_secret> -shcluster_label <new_cluster_name>

   # Bootstrap the new cluster
   sudo /opt/splunk/bin/splunk bootstrap shcluster-captain -servers_list "<new_member1>,<new_member2>,<new_member3>"
   ```

2. Migrate configurations and knowledge objects:

   ```bash
   # On the old deployer
   tar -czf shcluster_apps.tar.gz /opt/splunk/etc/shcluster/apps/
   tar -czf shcluster_users.tar.gz /opt/splunk/etc/shcluster/users/

   # Transfer to new deployer
   scp shcluster_apps.tar.gz shcluster_users.tar.gz new_deployer:/tmp/

   # On the new deployer
   sudo tar -xzf /tmp/shcluster_apps.tar.gz -C /opt/splunk/etc/shcluster/
   sudo tar -xzf /tmp/shcluster_users.tar.gz -C /opt/splunk/etc/shcluster/
   sudo /opt/splunk/bin/splunk apply shcluster-bundle --answer-yes
   ```

3. Update configurations to point to new indexers and cluster managers:

   ```bash
   sudo vi /opt/splunk/etc/shcluster/apps/search/local/distsearch.conf

   [distributedSearch]
   servers = <new_indexer1>:9997, <new_indexer2>:9997, ...

   sudo /opt/splunk/bin/splunk apply shcluster-bundle --answer-yes
   ```

4. Verify new SHC functionality:

   ```bash
   sudo /opt/splunk/bin/splunk show shcluster-status
   ```

5. Update load balancer to point to new SHC members

6. Gradually shift user traffic to the new SHC

## 5. Migrate Heavy Forwarders

1. Install Splunk on new heavy forwarder servers

2. Copy configurations from old to new heavy forwarders:

   ```bash
   scp -r /opt/splunk/etc/apps/* new-hf:/opt/splunk/etc/apps/
   scp /opt/splunk/etc/system/local/outputs.conf new-hf:/opt/splunk/etc/system/local/
   scp /opt/splunk/etc/system/local/inputs.conf new-hf:/opt/splunk/etc/system/local/
   ```

3. Update outputs.conf to point to new indexers:

   ```bash
   sudo vi /opt/splunk/etc/system/local/outputs.conf

   [tcpout]
   defaultGroup = primary_indexers

   [tcpout:primary_indexers]
   server = <new_indexer1>:9997, <new_indexer2>:9997, ...
   ```

4. Restart Splunk on new heavy forwarders:

   ```bash
   sudo /opt/splunk/bin/splunk restart
   ```

5. Verify data flow and gradually shift traffic to new heavy forwarders

## 6. Migrate Utility Server

1. Set up new utility server with necessary roles (license master, deployment server, monitoring console, etc.)

2. Migrate configurations from old to new utility server:

   ```bash
   # License Master migration
   sudo /opt/splunk/bin/splunk show license > old_license_info.txt
   sudo cp /opt/splunk/etc/licenses/enterprise.lic /tmp/
   scp /tmp/enterprise.lic new_utility:/tmp/
   sudo cp /tmp/enterprise.lic /opt/splunk/etc/licenses/

   # Deployment Server migration
   tar -czf deployment_apps.tar.gz /opt/splunk/etc/deployment-apps/
   tar -czf serverclass.tar.gz /opt/splunk/etc/system/local/serverclass.conf
   scp deployment_apps.tar.gz serverclass.tar.gz new_utility:/tmp/
   sudo tar -xzf /tmp/deployment_apps.tar.gz -C /opt/splunk/etc/
   sudo tar -xzf /tmp/serverclass.tar.gz -C /opt/splunk/etc/system/local/

   # Monitoring Console migration
   tar -czf monitoring_console_apps.tar.gz /opt/splunk/etc/apps/splunk_monitoring_console/
   scp monitoring_console_apps.tar.gz new_utility:/tmp/
   sudo tar -xzf /tmp/monitoring_console_apps.tar.gz -C /opt/splunk/etc/apps/
   ```

3. Update references in the environment to point to the new utility server:

   ```bash
   # Update all Splunk instances to point to the new license master
   sudo vi /opt/splunk/etc/system/local/server.conf

   [license]
   master_uri = https://<new_utility>:8089

   # Update all forwarders to point to the new deployment server
   sudo vi /opt/splunkforwarder/etc/system/local/deploymentclient.conf

   [deployment-client]
   phoneHomeIntervalInSecs = 600
   serverUrl = https://<new_utility>:8089

   # Restart all instances
   sudo /opt/splunk/bin/splunk restart
   sudo /opt/splunkforwarder/bin/splunk restart
   ```

## 7. Final Verification and Cutover

1. Verify all data is searchable and clusters are healthy:

   ```bash
   sudo /opt/splunk/bin/splunk show cluster-status --verbose
   sudo /opt/splunk/bin/splunk show shcluster-status
   ```

2. Run comprehensive tests on dashboards, alerts, and reports
3. Monitor system performance and license usage

## 8. Decommission Old Environment

1. Keep old environment running for a set period (e.g., 2-4 weeks) for rollback capability
2. Once confident in new environment, shut down old Splunk instances:

   ```bash
   sudo /opt/splunk/bin/splunk stop
   ```

3. Remove old Splunk installation and clean up data:

   ```bash
   sudo rm -rf /opt/splunk
   sudo rm -rf /path/to/splunk/indexes/*
   ```

**Note:** Throughout this process, maintain constant communication with stakeholders, monitor system health, and be prepared to rollback if necessary. This method allows for a gradual transition with minimal downtime and reduced risk.
