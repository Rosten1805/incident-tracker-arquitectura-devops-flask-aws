############################################
# EC2: jenkins-server y app-server
############################################

resource "aws_instance" "jenkins_server" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.jenkins_subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins_server.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins_ec2.name
  associate_public_ip_address = true

  user_data                   = file("${path.module}/user_data/jenkins.sh")
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-jenkins-server"
  })
}

resource "aws_instance" "app_server" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.app_subnet_id
  vpc_security_group_ids      = [aws_security_group.app_server.id]
  iam_instance_profile        = aws_iam_instance_profile.app_ec2.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data/app.sh.tpl", {
    aws_region   = var.aws_region
    log_group    = aws_cloudwatch_log_group.app.name
    project_name = var.project_name
  })
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-server"
  })
}
