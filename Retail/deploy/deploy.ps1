﻿#################
#
# Run to get the lasest AZ powershell commands (for stream analytics) NOTE:  Not all stream analytics components can be auto deployed
#
#################
#Install-Module -Name Az -AllowClobber -Scope CurrentUser
#################
$githubPath = "C:\github\solliancenet\cosmos-db-scenario-based-labs";
$mode = "lab"  #can be 'lab' or 'demo'
$subscriptionId = "YOUR SUBSCRIPTION ID"
$subName = "YOUR SUBSCRIPTION NAME"

#this should get set on a successful deployment...
$suffix = ""

$prefix = "YOUR INITIALS"
$rgName = $prefix + "_s2_retail"
$databaseId = "movies";

#register at https://api.themoviedb.org
$movieApiKey = "YOUR API KEY";

#toggles for skipping items
$skipDeployment = $false;


function DeployTemplate($filename, $skipDeployment, $parameters)
{
    write-host "Deploying $filename - Please wait";

    if (!$skipDeployment)
    {
        #deploy the template
        $deployId = "Microsoft.Template"
        $result = $(az group deployment create --name $deployId --resource-group $rgName --mode Incremental --template-file $($githubpath + "\retail\deploy\$fileName") --output json )#--parameters storageAccountType=Standard_GRS)

        #wait for the job to complete...
        $res = $(az group deployment list --resource-group $rgname --output json)
        $json = ConvertObjectToJson $res;

        $deployment = $json | where {$_.name -eq $deployId};

        #check the status
        while($deployment.properties.provisioningState -eq "Running")
        {
            start-sleep 10;

            $res = $(az group deployment list --resource-group $rgname --output json)
            $json = ConvertObjectToJson $res;

            $deployment = $json | where {$_.name -eq $deployId};

            write-host "Deployment status is : $($deployment.properties.provisioningState)";
        }

        write-host "Deploying finished with status $($deployment.properties.provisioningState)";
    }

    return $deployment;
}

function UpdateConfig($path)
{
    [xml]$xml = get-content $filepath;

    #set the function url
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "funcAPIUrl"}

    if($data)
    {
        $data.value = $funcApiUrl;
    }

    #set the function key
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "funcAPIKey"}

    if($data)
    {
        $data.value = $funcApiKey;
    }

    #set the database url
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "dbConnectionUrl"}

    if($data)
    {
        $data.value = $dbConnectionUrl;
    }

    #set the database key
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "dbConnectionKey"}

    if($data)
    {
        $data.value = $dbConnectionKey;
    }

    #set the movie api key
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "movieApiKey"}

    if($data)
    {
        $data.value = $movieApiKey;
    }

    #set the database id
    $data = $xml.configuration.appSettings.add | where {$_.key -eq "databaseId"}

    if($data)
    {
        $data.value = $databaseId;
    }

    $xml.save($filePath);    
}

function Output()
{
    write-host "Output variables:"

    write-host "Azure Queue: $azurequeueConnString"
    write-host "Func Url: $funcApiUrl"
    write-host "Func Key: $funcApiKey";
    write-host "Cosmos DB Url: $dbConnectionUrl"
    write-host "Cosmos DB Key: $dbConnectionKey"
    write-host "DatabaseId: $databaseId"
    write-host "EventHubConn: $eventHubConnection"
    write-host "CosmosDBFull: $CosmosDBConnection"
}

function SetupStreamAnalytics($suffix)
{
    #deploy the template
    $deployId = "Microsoft.Template"
    $result = $(az group deployment create --name $deployId --resource-group $rgName --mode Incremental --template-file $($githubpath + "\retail\deploy\labdeploy2.json") --output json )

    #wait for the job to complete...
    $res = $(az group deployment list --resource-group $rgname --output json)
    $json = ConvertObjectToJson $res;

    $deployment = $json | where {$_.name -eq $deployId};

    #https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-quick-create-powershell
    Connect-AzAccount -Subscription $subName

    $jobName = "s2_analytics_$suffix";

    #set the stream analytics inputs - TODO needs sharedaccesspolicykey...
    $jobInputName = "s2event"
    $jobInputDefinitionFile = "streamanaltyics_input_1.json"

    New-AzStreamAnalyticsInput -ResourceGroupName $rgName -JobName $jobName -File $jobInputDefinitionFile -Name $jobInputName;

    #set the stream analytics outputs (#1)
    $jobOutputName = "eventCount"
    $jobOutputDefinitionFile = "streamanaltyics_output_1.json"

    New-AzStreamAnalyticsOutput -ResourceGroupName $rgName -JobName $jobName -File $jobOutputDefinitionFile -Name $jobOutputName -Force

    #set the stream analytics outputs (#2)
    $jobOutputName = "eventOrdersLastHour"
    $jobOutputDefinitionFile = "streamanaltyics_output_2.json"

    New-AzStreamAnalyticsOutput -ResourceGroupName $rgName -JobName $jobName -File $jobOutputDefinitionFile -Name $jobOutputName -Force

    #set the stream analytics outputs (#3)
    $jobOutputName = "eventSummary"
    $jobOutputDefinitionFile = "streamanaltyics_output_3.json"

    New-AzStreamAnalyticsOutput -ResourceGroupName $rgName -JobName $jobName -File $jobOutputDefinitionFile -Name $jobOutputName -Force

    #set the stream analytics outputs (#4)
    $jobOutputName = "failureCount"
    $jobOutputDefinitionFile = "streamanaltyics_output_4.json"

    New-AzStreamAnalyticsOutput -ResourceGroupName $rgName -JobName $jobName -File $jobOutputDefinitionFile -Name $jobOutputName -Force

    #set the stream analytics outputs (#5)
    $jobOutputName = "userCount"
    $jobOutputDefinitionFile = "streamanaltyics_output_5.json"

    New-AzStreamAnalyticsOutput -ResourceGroupName $rgName -JobName $jobName -File $jobOutputDefinitionFile -Name $jobOutputName -Force

    #set the stream analytics query
    $jobTransformationName = "s2_retail_job"
    $jobTransformationDefinitionFile = "streamanaltyics_query.json"

    New-AzStreamAnalyticsTransformation -ResourceGroupName $rgName -JobName $jobName -File $jobTransformationDefinitionFile -Name $jobTransformationName -Force

    #start the job
    Start-AzStreamAnalyticsJob -ResourceGroupName $rgName -Name $jobName -OutputStartMode 'JobStartTime'
}

function ConvertObject($data)
{
    $str = "";
    foreach($c in $data)
    {
        $str += $c;
    }

    return $str;
}

function ConvertObjectToJson($data)
{
    $json = ConvertObject $data;

    return ConvertFrom-json $json;
}

cd $githubpath

#login - do this always as AAD will error if you change location/ip
$subs = az login;

#select the subscription if you set it
if ($subName)
{
    az account set --subscription $subName;
}

#create the resource group
$result = az group create --name $rgName --location "Central US"

#get all the resources in the RG
$res = $(az resource list --resource-group $rgName)
$json = ConvertObjectToJson $res;

$deployment = DeployTemplate "labdeploy.json" $skipDeployment;

#need the suffix...
if ($deployment.properties.provisioningState -eq "Succeeded")
{
    $suffix = $deployment.properties.outputs.hash.value
}

$saJob = $json | where {$_.type -eq "Microsoft.StreamAnalytics/streamingjobs"};

if (!$saJob)
{
    #deploy stream analytics
    $deployment = DeployTemplate "labdeploy2.json" $skipDeployment;
}

$logicApp = $json | where {$_.type -eq "Microsoft.Logic/workflows"};

if (!$logicApp)
{
    #deploy logic app
    $deployment = DeployTemplate "labdeploy3.json" $skipDeployment;
}

#used later
$funcAppName = "s2func" + $suffix;
$funcApp = $json | where {$_.type -eq "Microsoft.Web/sites" -and $_.name -eq $funcAppName};

#deploy containers - this is ok to fail
$deployment = DeployTemplate "labdeploy4.json" $skipDeployment;

#get all the settings
$azurequeueConnString = "";
$paymentsApiUrl = "";
$funcApiUrl = "";
$funcApiKey = "";
$dbConnectionUrl = "";
$dbConnectionKey = "";
$databaseId = "movies"
$eventHubConnection = "";
$CosmosDBConnection = "";

########################
#
#get the event hub connection
#
########################
write-host "Getting event hub connection"

$res = $(az eventhubs namespace list --output json --resource-group $rgName)
$json = ConvertObjectToJson $res;

$sa = $json | where {$_.name -eq "s2ns" + $suffix};
$res = $(az eventhubs namespace authorization-rule keys list --resource-group $rgName --namespace-name $sa.name --name RootManageSharedAccessKey)
$json = ConvertObjectToJson $res;

$eventHubConnection = $json.primaryConnectionString

########################
#
#get the storage connection string
#
########################
write-host "Getting storage account key"

$res = $(az storage account list --output json --resource-group $rgName)
$json = ConvertObjectToJson $res;

$sa = $json | where {$_.name -eq "s2data3" + $suffix};

$res = $(az storage account keys list --account-name $sa.name)
$json = ConvertObjectToJson $res;

$key = $json[0].value;

$azurequeueConnString = "DefaultEndpointsProtocol=https;AccountName=$($sa.name);AccountKey=$($key);EndpointSuffix=core.windows.net";

########################
#
#get the cosmos db url and key
#
#########################
write-host "Getting cosmos db url and key"

$res = $(az cosmosdb list --output json --resource-group $rgName)
$json = ConvertObjectToJson $res;

$db = $json | where {$_.name -eq "s2cosmosdb" + $suffix};

$dbConnectionUrl = $db.documentEndpoint;

$res = $(az cosmosdb keys list --name $db.name --resource-group $rgName)
$json = ConvertObjectToJson $res;

$dbConnectionKey = $json.primaryMasterKey;

$CosmosDBConnection = "AccountEndpoint=$dbConnectionUrl;AccountKey=$dbConnectionKey";

########################
#
#deploy the web app
#
#########################
$webAppName = "s2web" + $suffix;

if ($mode -eq "demo")
{ 
    write-host "Deploying the web application"

    $res = $(az webapp deployment source config-zip --resource-group $rgName --name $webAppName --src "$githubpath/retail/deploy/webapp.zip")
    $json = ConvertObjectToJson $res;
}

########################
#
#deploy the function
#
#########################

$funcAppName = "s2func" + $suffix;

#we have to deploy something in order for the host.json file to be created in the storage account...
if ($mode -eq "demo")
{
    write-host "Deploying the function app"

    $res = $(az functionapp deployment source config-zip --resource-group $rgName --name $funcAppName --src "$githubpath/retail/deploy/functionapp.zip")
    $json = ConvertObjectToJson $res;
}

########################
#
#get the function url and key
#
#########################
write-host "Getting the function app url and key"

$res = $(az functionapp list --output json --resource-group $rgName)
$json = ConvertObjectToJson $res;

$func = $json | where {$_.name -eq $funcAppName};

$funcApiUrl = "https://" + $func.defaultHostName;

#open the function app endpoint to create the host.json file:
$url = "https://$($func.defaultHostName)/admin/vfs/site/wwwroot/host.json"
Start-Process $url;

start-sleep 5;

#key is stored in the storage account after the last url loads.
$res = $(az storage blob list --connection-string $azurequeueConnString --container-name azure-webjobs-secrets)
$json = ConvertObjectToJson $res;

$blob = $json | where {$_.name -eq "$funcAppName/host.json"};

if (!$blob)
{
    write-host "The function app did not load the url, the host.json file is not available";
    return;
}

#download it..
az storage blob download --connection-string $azurequeueConnString --container-name azure-webjobs-secrets --name $blob.name --file host.json;

$data = Get-content "host.json" -raw
$json = ConvertFrom-json $data;

$funcApiKey = $json.masterkey.value;

########################
#
#set the web app properties
#
#########################
write-host "Saving app settings to web application"

$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings AzureQueueConnectionString=$azurequeueConnString)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings paymentsAPIUrl=$paymentsApiUrl)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings funcAPIUrl=$funcApiUrl)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings funcAPIKey=$funcApiKey)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings databaseId=$databaseId)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings dbConnectionUrl=$dbConnectionUrl)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings dbConnectionKey=$dbConnectionKey)
$res = $(az webapp config appsettings set -g $rgName -n $webAppName --settings movieApiKey=$movieApiKey)


########################
#
#set the func properties
#
#########################
write-host "Saving app settings to func app"

$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings AzureQueueConnectionString=$azurequeueConnString)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings paymentsAPIUrl=bl$paymentsApiUrlah)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings funcAPIUrl=$funcApiUrl)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings funcAPIKey=$funcApiKey)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings databaseId=$databaseId)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings CosmosDBConnection=$CosmosDBConnection)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings dbConnectionUrl=$dbConnectionUrl)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings dbConnectionKey=$dbConnectionKey)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings eventHubConnection=$eventHubConnection)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings eventHub=store)
$res = $(az webapp config appsettings set -g $rgName -n $funcAppName --settings movieApiKey=$movieApiKey)

########################
#
#Update project configs to be nice ;)
#
########################
write-host "Saving app settings to Visual Studio solutions (starter and solution)"

$folders = ("starter", "solution")

foreach($folder in $folders)
{
    $filePath = "$githubpath\lab-files\Retail\$folder\Data Import\app.config"
    UpdateConfig $filePath;

    $filePath = "$githubpath\lab-files\Retail\$folder\DataGenerator\app.config"
    UpdateConfig $filePath;

    $filePath = "$githubpath\lab-files\Retail\$folder\Contoso Movies\Contoso.Apps.Movies.Web\web.config"
    UpdateConfig $filePath;

    #update the app.config file with the new values
    $filePath = "$githubpath\lab-files\Retail\$folder\Data Import\bin\Debug\MovieDataImport.exe.config"
    UpdateConfig $filePath;
}

########################
#
#setup the cosmosdb (run the import tool to create collections and import initial object data)
#
########################
if ($mode -eq "demo")
{ 
    write-host "Importing all the movie data"

    #run the import tool
    . "$githubpath\lab-files\Retail\Starter\Data Import\bin\Debug\MovieDataImport.exe"
}

########################
#
#deploy stream analytics - Not production ready - does not support Power BI Outputs
#
#########################
#SetupStreamAnalytics $suffix;

########################
#
#run the data bricks notebook - Future
#
########################

if ($mode -eq "demo")
{
    #create the node

    #import the notebooks

    #update the variables

    #execute the notebook
}

########################
#
# Output variables
#
########################
Output