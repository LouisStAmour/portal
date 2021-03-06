###
# ECS - Portal
###

# Task Definition

data "github_branch" "portal" {
  repository = "portal"
  branch     = "master"
}

data "template_file" "covidshield_portal_task" {
  template = file("task-definitions/covidshield_portal.json")

  vars = {
    image                    = "covidshield/portal:${coalesce(var.github_sha, data.github_branch.portal.sha)}"
    awslogs-group            = data.terraform_remote_state.backend.outputs.cloudwatch_log_group.name
    awslogs-region           = var.region
    awslogs-stream-prefix    = "ecs-${var.ecs_portal_name}"
    rails_master_key         = aws_secretsmanager_secret_version.portal_env_rails_master_key.arn
    database_url             = aws_secretsmanager_secret_version.portal_database_url.arn
    rails_env                = var.ecs_task_portal_env_rails_env
    rails_serve_static_files = var.ecs_task_portal_env_rails_serve_static_files
    key_claim_host           = data.terraform_remote_state.backend.outputs.route53_submission_fqdn.name
  }
}

resource "aws_ecs_task_definition" "covidshield_portal" {
  family       = var.ecs_portal_name
  cpu          = 1024
  memory       = "2048"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.covidshield_portal.arn
  task_role_arn            = aws_iam_role.covidshield_portal.arn
  container_definitions    = data.template_file.covidshield_portal_task.rendered

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

# Service

resource "aws_ecs_service" "covidshield_portal" {
  depends_on = [
    aws_lb_listener.covidshield_portal,
  ]

  name            = var.ecs_portal_name
  cluster         = data.terraform_remote_state.backend.outputs.ecs_cluster.id
  task_definition = aws_ecs_task_definition.covidshield_portal.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  # Enable the new ARN format to propagate tags to containers
  propagate_tags = "SERVICE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  network_configuration {
    assign_public_ip = false
    subnets          = data.terraform_remote_state.backend.outputs.aws_private_subnets.*.id
    security_groups = [
      data.terraform_remote_state.backend.outputs.security_group_egress_anywhere.id,
      aws_security_group.covidshield_portal.id,
    ]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.covidshield_portal.arn
    container_name   = "portal"
    container_port   = 3000
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}
