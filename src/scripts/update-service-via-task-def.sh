set -o noglob

[ -f /tmp/workspace/new-env-vars ] && . /tmp/workspace/new-env-vars

# These variables are evaluated so the config file may contain and pass in environment variables to the parameters.
ECS_PARAM_FAMILY=$(eval echo "$ECS_PARAM_FAMILY")
ECS_PARAM_CLUSTER_NAME=$(eval echo "$ECS_PARAM_CLUSTER_NAME")
ECS_PARAM_SERVICE_NAME=$(eval echo "$ECS_PARAM_SERVICE_NAME")

if [ -z "${ECS_PARAM_SERVICE_NAME}" ]; then
    ECS_PARAM_SERVICE_NAME="$ECS_PARAM_FAMILY"
fi

if [ "$ECS_PARAM_FORCE_NEW_DEPLOY" == "1" ]; then
    set -- "$@" --force-new-deployment
fi

DEPLOYED_REVISION=$(aws ecs update-service \
    --cluster "$ECS_PARAM_CLUSTER_NAME" \
    --service "${ECS_PARAM_SERVICE_NAME}" \
    --task-definition "${CCI_ORB_AWS_ECS_REGISTERED_TASK_DFN}" \
    --output text \
    --query service.taskDefinition \
    "$@")
echo "export CCI_ORB_AWS_ECS_DEPLOYED_REVISION='${DEPLOYED_REVISION}'" >> "$BASH_ENV"