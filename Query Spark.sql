﻿git checkout <branch>
git pull
databricks workspace export_dir --profile <profile> -o <path> ./Workspace

dt=`date '+%Y-%m-%d %H:%M:%S'`
msg_default="DB export on $dt"
read -p "Enter the commit comment [$msg_default]: " msg
msg=${msg:-$msg_default}
echo $msg

git add .
git commit -m "<commit-message>"
git push

# Azure Databricks Build Pipeline
# azure-pipelines.yml

trigger:
- release

pool:
  name: Hosted Ubuntu 1604

steps:
- task: UsePythonVersion@0
  displayName: 'Use Python 3.7'
  inputs:
    versionSpec: 3.7

- script: |
    pip install pytest requests setuptools wheel
    pip install -U databricks-connect==6.4.*
  displayName: 'Load Python Dependencies'

- script: |
    echo "y
    $(WORKSPACE-REGION-URL)
    $(CSE-DEVELOP-PAT)
    $(EXISTING-CLUSTER-ID)
    $(WORKSPACE-ORG-ID)
    15001" | databricks-connect configure
  displayName: 'Configure DBConnect'

- checkout: self
  persistCredentials: true
  clean: true

- script: git checkout release
  displayName: 'Get Latest Branch'

- script: |
    python -m pytest --junit-xml=$(Build.Repository.LocalPath)/logs/TEST-LOCAL.xml
$(Build.Repository.LocalPath)/libraries/python/dbxdemo/test*.py || true

  displayName: 'Run Python Unit Tests for library code'

- task: PublishTestResults@2
  inputs:
    testResultsFiles: '**/TEST-*.xml'
    failTaskOnFailedTests: true
    publishRunAttachments: true

- script: |
    cd $(Build.Repository.LocalPath)/libraries/python/dbxdemo
    python3 setup.py sdist bdist_wheel
    ls dist/
  displayName: 'Build Python Wheel for Libs'

- script: |
    git diff --name-only --diff-filter=AMR HEAD^1 HEAD | xargs -I '{}' cp --parents -r '{}' $(Build.BinariesDirectory)

    mkdir -p $(Build.BinariesDirectory)/libraries/python/libs
    cp $(Build.Repository.LocalPath)/libraries/python/dbxdemo/dist/*.* $(Build.BinariesDirectory)/libraries/python/libs

    mkdir -p $(Build.BinariesDirectory)/cicd-scripts
    cp $(Build.Repository.LocalPath)/cicd-scripts/*.* $(Build.BinariesDirectory)/cicd-scripts

  displayName: 'Get Changes'

- task: ArchiveFiles@2
  inputs:
    rootFolderOrFile: '$(Build.BinariesDirectory)'
    includeRootFolder: false
    archiveType: 'zip'
    archiveFile: '$(Build.ArtifactStagingDirectory)/$(Build.BuildId).zip'
    replaceExistingArchive: true

- task: PublishBuildArtifacts@1
  inputs:
    ArtifactName: 'DatabricksBuild'

    # Specify the trigger event to start the build pipeline.
# In this case, new code merged into the release branch initiates a new build.
trigger:
- release

# Specify the OS for the agent
pool:
  name: Hosted Ubuntu 1604

# Install Python. The version must match the version on the Databricks cluster.
steps:
- task: UsePythonVersion@0
  displayName: 'Use Python 3.7'
  inputs:
    versionSpec: 3.7

# Install required Python modules, including databricks-connect, required to execute a unit test
# on a cluster.
- script: |
    pip install pytest requests setuptools wheel
    pip install -U databricks-connect==6.4.*
  displayName: 'Load Python Dependencies'

# Use environment variables to pass Databricks login information to the Databricks Connect
# configuration function
- script: |
    echo "y
    $(WORKSPACE-REGION-URL)
    $(CSE-DEVELOP-PAT)
    $(EXISTING-CLUSTER-ID)
    $(WORKSPACE-ORG-ID)
    15001" | databricks-connect configure
  displayName: 'Configure DBConnect'

  - checkout: self
  persistCredentials: true
  clean: true

- script: git checkout release
  displayName: 'Get Latest Branch'

  - script: |
    python -m pytest --junit-xml=$(Build.Repository.LocalPath)/logs/TEST-LOCAL.xml $(Build.Repository.LocalPath)/libraries/python/dbxdemo/test*.py || true
    ls logs
  displayName: 'Run Python Unit Tests for library code'

  # addcol.py
import pyspark.sql.functions as F

def with_status(df):
    return df.withColumn("status", F.lit("checked"))

    # test-addcol.py
import pytest

from dbxdemo.spark import get_spark
from dbxdemo.appendcol import with_status

class TestAppendCol(object):

    def test_with_status(self):
        source_data = [
            ("pete", "pan", "peter.pan@databricks.com"),
            ("jason", "argonaut", "jason.argonaut@databricks.com")
        ]
        source_df = get_spark().createDataFrame(
            source_data,
            ["first_name", "last_name", "email"]
        )

        actual_df = with_status(source_df)

        expected_data = [
            ("pete", "pan", "peter.pan@databricks.com", "checked"),
            ("jason", "argonaut", "jason.argonaut@databricks.com", "checked")
        ]
        expected_df = get_spark().createDataFrame(
            expected_data,
            ["first_name", "last_name", "email", "status"]
        )

        assert(expected_df.collect() == actual_df.collect())

        - script: |
    cd $(Build.Repository.LocalPath)/libraries/python/dbxdemo
    python3 setup.py sdist bdist_wheel
    ls dist/
  displayName: 'Build Python Wheel for Libs'- task: PublishTestResults@2
  inputs:
    testResultsFiles: '**/TEST-*.xml'
    failTaskOnFailedTests: true
    publishRunAttachments: true

    # installWhlLibrary.py
#!/usr/bin/python3
import json
import requests
import sys
import getopt
import time
import os

def main():
    shard = ''
    token = ''
    clusterid = ''
    libspath = ''
    dbfspath = ''

    try:
        opts, args = getopt.getopt(sys.argv[1:], 'hstcld',
                                   ['shard=', 'token=', 'clusterid=', 'libs=', 'dbfspath='])
    except getopt.GetoptError:
        print(
            'installWhlLibrary.py -s <shard> -t <token> -c <clusterid> -l <libs> -d <dbfspath>')
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print(
                'installWhlLibrary.py -s <shard> -t <token> -c <clusterid> -l <libs> -d <dbfspath>')
            sys.exit()
        elif opt in ('-s', '--shard'):
            shard = arg
        elif opt in ('-t', '--token'):
            token = arg
        elif opt in ('-c', '--clusterid'):
            clusterid = arg
        elif opt in ('-l', '--libs'):
            libspath=arg
        elif opt in ('-d', '--dbfspath'):
            dbfspath=arg

    print('-s is ' + shard)
    print('-t is ' + token)
    print('-c is ' + clusterid)
    print('-l is ' + libspath)
    print('-d is ' + dbfspath)

    # Uninstall library if exists on cluster
    i=0

    # Generate array from walking local path
    libslist = []
    for path, subdirs, files in os.walk(libspath):
        for name in files:

            name, file_extension = os.path.splitext(name)
            if file_extension.lower() in ['.whl']:
                libslist.append(name + file_extension.lower())

    for lib in libslist:
        dbfslib = dbfspath + '/' + lib

        if (getLibStatus(shard, token, clusterid, dbfslib) is not None:
            print(dbfslib + ' before:' + getLibStatus(shard, token, clusterid, dbfslib))
            print(dbfslib + " exists. Uninstalling.")
            i = i + 1
            values = {'cluster_id': clusterid, 'libraries': [{'whl': dbfslib}]}

            resp = requests.post(shard + '/api/2.0/libraries/uninstall', data=json.dumps(values), auth=("token", token))
            runjson = resp.text
            d = json.loads(runjson)
            print(dbfslib + ' after:' + getLibStatus(shard, token, clusterid, dbfslib))

            # Restart if libraries uninstalled
            if i > 0:
                values = {'cluster_id': clusterid}
                print("Restarting cluster:" + clusterid)
                resp = requests.post(shard + '/api/2.0/clusters/restart', data=json.dumps(values), auth=("token", token))
                restartjson = resp.text
                print(restartjson)

                p = 0
                waiting = True
                while waiting:
                    time.sleep(30)
                    clusterresp = requests.get(shard + '/api/2.0/clusters/get?cluster_id=' + clusterid,
                                           auth=("token", token))
                    clusterjson = clusterresp.text
                    jsonout = json.loads(clusterjson)
                    current_state = jsonout['state']
                    print(clusterid + " state:" + current_state)
                    if current_state in ['TERMINATED', 'RUNNING','INTERNAL_ERROR', 'SKIPPED'] or p >= 10:
                        break
                    p = p + 1

        print("Installing " + dbfslib)
        values = {'cluster_id': clusterid, 'libraries': [{'whl': 'dbfs:' + dbfslib}]}

        resp = requests.post(shard + '/api/2.0/libraries/install', data=json.dumps(values), auth=("token", token))
        runjson = resp.text
        d = json.loads(runjson)
        print(dbfslib + ' after:' + getLibStatus(shard, token, clusterid, dbfslib))

def getLibStatus(shard, token, clusterid, dbfslib):

    resp = requests.get(shard + '/api/2.0/libraries/cluster-status?cluster_id='+ clusterid, auth=("token", token))
    libjson = resp.text
    d = json.loads(libjson)
    if (d.get('library_statuses')):
        statuses = d['library_statuses']

        for status in statuses:
            if (status['library'].get('whl')):
                if (status['library']['whl'] == 'dbfs:' + dbfslib):
                    return status['status']
    else:
        # No libraries found
        return "not found"

if __name__ == '__main__':
    main()

    # executenotebook.py
#!/usr/bin/python3
import json
import requests
import os
import sys
import getopt
import time

def main():
    shard = ''
    token = ''
    clusterid = ''
    localpath = ''
    workspacepath = ''
    outfilepath = ''

    try:
        opts, args = getopt.getopt(sys.argv[1:], 'hs:t:c:lwo',
                                   ['shard=', 'token=', 'clusterid=', 'localpath=', 'workspacepath=', 'outfilepath='])
    except getopt.GetoptError:
        print(
            'executenotebook.py -s <shard> -t <token>  -c <clusterid> -l <localpath> -w <workspacepath> -o <outfilepath>)')
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print(
                'executenotebook.py -s <shard> -t <token> -c <clusterid> -l <localpath> -w <workspacepath> -o <outfilepath>')
            sys.exit()
        elif opt in ('-s', '--shard'):
            shard = arg
        elif opt in ('-t', '--token'):
            token = arg
        elif opt in ('-c', '--clusterid'):
            clusterid = arg
        elif opt in ('-l', '--localpath'):
            localpath = arg
        elif opt in ('-w', '--workspacepath'):
            workspacepath = arg
        elif opt in ('-o', '--outfilepath'):
            outfilepath = arg

    print('-s is ' + shard)
    print('-t is ' + token)
    print('-c is ' + clusterid)
    print('-l is ' + localpath)
    print('-w is ' + workspacepath)
    print('-o is ' + outfilepath)
    # Generate array from walking local path

    notebooks = []
    for path, subdirs, files in os.walk(localpath):
        for name in files:
            fullpath = path + '/' + name
            # removes localpath to repo but keeps workspace path
            fullworkspacepath = workspacepath + path.replace(localpath, '')

            name, file_extension = os.path.splitext(fullpath)
            if file_extension.lower() in ['.scala', '.sql', '.r', '.py']:
                row = [fullpath, fullworkspacepath, 1]
                notebooks.append(row)

    # run each element in array
    for notebook in notebooks:
        nameonly = os.path.basename(notebook[0])
        workspacepath = notebook[1]

        name, file_extension = os.path.splitext(nameonly)

        # workpath removes extension
        fullworkspacepath = workspacepath + '/' + name

        print('Running job for:' + fullworkspacepath)
        values = {'run_name': name, 'existing_cluster_id': clusterid, 'timeout_seconds': 3600, 'notebook_task': {'notebook_path': fullworkspacepath}}

        resp = requests.post(shard + '/api/2.0/jobs/runs/submit',
                             data=json.dumps(values), auth=("token", token))
        runjson = resp.text
        print("runjson:" + runjson)
        d = json.loads(runjson)
        runid = d['run_id']

        i=0
        waiting = True
        while waiting:
            time.sleep(10)
            jobresp = requests.get(shard + '/api/2.0/jobs/runs/get?run_id='+str(runid),
                             data=json.dumps(values), auth=("token", token))
            jobjson = jobresp.text
            print("jobjson:" + jobjson)
            j = json.loads(jobjson)
            current_state = j['state']['life_cycle_state']
            runid = j['run_id']
            if current_state in ['TERMINATED', 'INTERNAL_ERROR', 'SKIPPED'] or i >= 12:
                break
            i=i+1

        if outfilepath != '':
            file = open(outfilepath + '/' +  str(runid) + '.json', 'w')
            file.write(json.dumps(j))
            file.close()

if __name__ == '__main__':
    main()
    # evaluatenotebookruns.py
import unittest
import json
import glob
import os

class TestJobOutput(unittest.TestCase):

    test_output_path = '#ENV#'

    def test_performance(self):
        path = self.test_output_path
        statuses = []

        for filename in glob.glob(os.path.join(path, '*.json')):
            print('Evaluating: ' + filename)
            data = json.load(open(filename))
            duration = data['execution_duration']
            if duration > 100000:
                status = 'FAILED'
            else:
                status = 'SUCCESS'

            statuses.append(status)

        self.assertFalse('FAILED' in statuses)

    def test_job_run(self):
        path = self.test_output_path
        statuses = []

        for filename in glob.glob(os.path.join(path, '*.json')):
            print('Evaluating: ' + filename)
            data = json.load(open(filename))
            status = data['state']['result_state']
            statuses.append(status)

        self.assertFalse('FAILED' in statuses)

if __name__ == '__main__':
    unittest.main()
    hive 

hive > show DATABASE;
bigdata_klabin-- Insert rows into table 'Klabin';
INSERT INTO Klabin
( -- columns to insert data into
 [Licença Office], [SQL], [Servidores], [Adobe], [Autodesk]
)
VALUES
( -- first row: values for the columns in the list above
 STRING_AGG(Nome), STRING_AGG(Nome), STRING_AGG(ProductName), STRING_AGG(ProductName), STRING_AGG(Version)
),
( -- second row: values for the columns in the list above
 STRING_AGG(Version), STRING_AGG(ProductName), STRING_AGG(Version), INTEGER(NetBios), INTEGER(NetBios)
)
-- add more rows here
GO

-- Create a new stored procedure called 'StoredProcedureName' in schema 'SchemaName'
-- Drop the stored procedure if it already exists
IF EXISTS (
SELECT *
    FROM INFORMATION_SCHEMA.ROUTINES
WHERE SPECIFIC_SCHEMA = N'Big Data Klabin'
    AND SPECIFIC_NAME = N'Lincenciamento de software Klabin: Projeto Gestão de Ativos'
)
DROP PROCEDURE SchemaName.Big Data Klabin
GO
-- Create the stored procedure in the specified schema
CREATE PROCEDURE SchemaName.StoredProcedureName
    @param1 /len VALUES/ int /STRING_AGG(Nome)/ = 0, /default/
    @param2 /len second row/ int /STRING_AGG(Version)/ = 0 /default/
-- add more stored procedure parameters here
AS
    -- body of the stored procedure
    SELECT @param1, @param2
GO
-- example to execute the stored procedure we just created
EXECUTE SchemaName.StoredProcedureName 1 /-- Get a list of tables and views in the current database
SELECT table_catalog [database], table_schema [schema], table_name name, table_type type
FROM INFORMATION_SCHEMA.TABLES
GO/, 2 /*value_for_param2*/
GO

create database klabin Gestão de ativos
set hive.cli.print.header = TRUE

show tables;
desc klabin big data;
insert into table teste01(1);
insert into table teste01 values(1);
select * from teste01;
insert into table teste01 values(2);
