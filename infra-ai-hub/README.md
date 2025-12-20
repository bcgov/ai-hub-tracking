# AI Hub Specific Infra
## placeholder with validation of access to data plane in azure from github hosted runner.
## if deployments contains azure kv, the deployment would fail for the first time to write to it,as the owner of the subscription, user needs to provide access to the managed identity for that specific kv it is a chicken vs egg story, so for all the kv data plane operations it will fail for the first time.
