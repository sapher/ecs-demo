resource "aws_security_group" "db" {
  name   = "${var.env}-db"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    protocol        = "tcp"
    to_port         = 5432
    security_groups = [aws_security_group.api.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "this" {
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "this" {
  identifier             = "${var.env}-testing"
  allocated_storage      = 10
  instance_class         = "db.t3.micro"
  engine                 = "postgres"
  engine_version         = "13.3"
  username               = local.db_credentials.user
  password               = local.db_credentials.pass
  db_name                = local.db_credentials.name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  multi_az               = false
}
