# These variables are evaluated so the config file may contain and pass in environment variables to the parameters.
ECS_PARAM_CLUSTER_NAME=$(eval echo "$ECS_PARAM_CLUSTER_NAME")
ECS_PARAM_TASK_DEF=$(eval echo "$ECS_PARAM_TASK_DEF")

set -o noglob
if [ "$ECS_PARAM_LAUNCH_TYPE" == "FARGATE" ]; then
    echo "Setting --platform-version"
    set -- "$@" --platform-version "$ECS_PARAM_PLATFORM_VERSION"
fi
if [ -n "$ECS_PARAM_STARTED_BY" ]; then
    echo "Setting --started-by"
    set -- "$@" --started-by "$ECS_PARAM_STARTED_BY"
fi
if [ -n "$ECS_PARAM_GROUP" ]; then
    echo "Setting --group"
    set -- "$@" --group "$ECS_PARAM_GROUP"
fi
if [ -n "$ECS_PARAM_OVERRIDES" ]; then
    echo "Setting --overrides"
    set -- "$@" --overrides "$ECS_PARAM_OVERRIDES"
fi
if [ -n "$ECS_PARAM_TAGS" ]; then
    echo "Setting --tags"
    set -- "$@" --tags "$ECS_PARAM_TAGS"
fi
if [ -n "$ECS_PARAM_PLACEMENT_CONSTRAINTS" ]; then
    echo "Setting --placement-constraints"
    set -- "$@" --placement-constraints "$ECS_PARAM_PLACEMENT_CONSTRAINTS"
fi
if [ -n "$ECS_PARAM_PLACEMENT_STRATEGY" ]; then
    echo "Setting --placement-strategy"
    set -- "$@" --placement-strategy "$ECS_PARAM_PLACEMENT_STRATEGY"
fi
if [ "$ECS_PARAM_ENABLE_ECS_MANAGED_TAGS" == "1" ]; then
    echo "Setting --enable-ecs-managed-tags"
    set -- "$@" --enable-ecs-managed-tags
fi
if [ "$ECS_PARAM_PROPAGATE_TAGS" == "1" ]; then
    echo "Setting --propagate-tags"
    set -- "$@" --propagate-tags "TASK_DEFINITION"
fi
if [ "$ECS_PARAM_WAIT_FOR_TASK" == "1" ]; then
    echo "Setting --query 'tasks[].taskArn' --output text"
    set -- "$@" --query 'tasks[].taskArn' --output text
fi
if [ "$ECS_PARAM_SKIP_TASK_DEF_REG" == "0" ]; then
    echo "Setting --task-definition to previous registered TASK_DEF"
    ECS_PARAM_TASK_DEF=$(eval echo "$CCI_ORB_AWS_ECS_REGISTERED_TASK_DFN")
fi
if [ "$ECS_PARAM_AWSVPC" == "1" ]; then
    echo "Setting --network-configuration"
    if [ -n "$ECS_COPY_NETWORK_FROM_SERVICE" ]; then
        SERVICE_JSON=$(aws ecs describe-services --services $ECS_COPY_NETWORK_FROM_SERVICE --cluster $ECS_PARAM_CLUSTER_NAME)
        if [ -n "$SERVICE_JSON" ]; then
            ECS_PARAM_SUBNET_ID=$(echo $SERVICE_JSON | jq -c '.services[0].networkConfiguration.awsvpcConfiguration.subnets' | tr -d '[]"')
            ECS_PARAM_SEC_GROUP_ID=$(echo $SERVICE_JSON | jq -c '.services[0].networkConfiguration.awsvpcConfiguration.securityGroups' | tr -d '[]"')
            ECS_PARAM_ASSIGN_PUB_IP=$(echo $SERVICE_JSON | jq -c '.services[0].networkConfiguration.awsvpcConfiguration.assignPublicIp' | tr -d '[]"')
        else
            echo "Cannot query serive $ECS_COPY_NETWORK_FROM_SERVICE in cluster $ECS_PARAM_CLUSTER_NAME"
            exit 1
        fi
    fi


    if [ -z "$ECS_PARAM_SUBNET_ID" ]; then
        echo '"subnet-ids" is missing.'
        echo 'When "awsvpc" is enabled, "subnet-ids" must be provided.'
        exit 1
    fi
    ECS_PARAM_SUBNET_ID=$(eval echo "$ECS_PARAM_SUBNET_ID")
    ECS_PARAM_SEC_GROUP_ID=$(eval echo "$ECS_PARAM_SEC_GROUP_ID")
    set -- "$@" --network-configuration awsvpcConfiguration="{subnets=[$ECS_PARAM_SUBNET_ID],securityGroups=[$ECS_PARAM_SEC_GROUP_ID],assignPublicIp=$ECS_PARAM_ASSIGN_PUB_IP}"
fi
if [ -n "$ECS_PARAM_CAPACITY_PROVIDER_STRATEGY" ]; then
    echo "Setting --capacity-provider-strategy"
    # do not quote
    # shellcheck disable=SC2086
    set -- "$@" --capacity-provider-strategy $ECS_PARAM_CAPACITY_PROVIDER_STRATEGY
fi

if [ -n "$ECS_PARAM_LAUNCH_TYPE" ]; then
    if [ -n "$ECS_PARAM_CAPACITY_PROVIDER_STRATEGY" ]; then
        echo "Error: "
        echo 'If a "capacity-provider-strategy" is specified, the "launch-type" parameter must be set to an empty string.'
        exit 1
    else
        echo "Setting --launch-type"
        set -- "$@" --launch-type "$ECS_PARAM_LAUNCH_TYPE"
    fi
fi

echo "Setting --count"
set -- "$@" --count "$ECS_PARAM_COUNT"
echo "Setting --task-definition"
set -- "$@" --task-definition $ECS_PARAM_TASK_DEF
echo "Setting --cluster"
set -- "$@" --cluster "$ECS_PARAM_CLUSTER_NAME"

ARN_VAL=$(aws ecs run-task "$@")
TASK_ID=$(echo $ARN_VAL | cut -d '/' -f 3)

if [ "$ECS_PARAM_WAIT_FOR_TASK" == "1" ]; then
    echo "Task has been initiated... the TaskARN is ${ARN_VAL}"
    echo "Wait until the task's container reaches the STOPPED state..."
    echo "Click below for the task output"
    echo "https://app.datadoghq.com/logs?event&index=%2A&query=task_arn%3A%22${ECS_PARAM_CLUSTER_NAME}%2F${TASK_ID}%22"
    aws ecs wait tasks-stopped --cluster $ECS_PARAM_CLUSTER_NAME --tasks $ARN_VAL
    EXIT_VAL=$(echo $(($(aws ecs describe-tasks --cluster $ECS_PARAM_CLUSTER_NAME --tasks $ARN_VAL --query 'tasks[0].containers[*].exitCode' --output text | tr -s '\t' '+'))))
    if [ "$EXIT_VAL" = "0" ]
    then
        echo "Taskexecution was successful!"
    else
        echo "Errors encountered while command... please check datadog for logs"
        TASK_ID=$(echo $ARN_VAL | cut -d '/' -f 3)
        exit $EXIT_VAL
    fi
fi

