
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-arm64-gp2"
}


resource "aws_launch_template" "Lab-Launch-Template" {
  name = join("", [var.DeploymentName, "-Launch-Template"])
  image_id = data.aws_ssm_parameter.ami.value
  instance_initiated_shutdown_behavior = "terminate"
  instance_market_options {
    market_type = "spot"
  }
  instance_type = "t4g.micro"
}


resource "aws_vpc" "RadLabVPC" {
  cidr_block                       = var.VPC_CIDR
  instance_tenancy                 = "default"
  enable_dns_hostnames             = "true"
  assign_generated_ipv6_cidr_block = "true"
  tags = {
    Name = "${var.DeploymentName}-VPC"
  }
}


resource "aws_security_group" "ssh-only-sg" {
  name        = "ssh-only-sg"
  description = "Allow http(s)"
  vpc_id      = aws_vpc.RadLabVPC.id

  ingress = [
    {
      description      = "ssh traffic"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    },
    {
      description      = "nat64 traffic"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = []
      ipv6_cidr_blocks = ["64:ff9b::/96"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]

  egress = [
    {
      description      = "Default rule"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]


  tags = {
    Name = "allow_ssh"
  }
}


resource "aws_subnet" "Pub-Dual-Subnet" {
  vpc_id                          = aws_vpc.RadLabVPC.id
  cidr_block                      = cidrsubnet(aws_vpc.RadLabVPC.cidr_block, 8, 0)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.RadLabVPC.ipv6_cidr_block, 8, 0)
  availability_zone               = data.aws_availability_zones.AZs.names[0]
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = true
  tags = {
    Name = join("", ["Pub-Dual-Sub-", var.DeploymentName])
  }
}


resource "aws_lambda_layer_version" "boto3_lambda_layer" {
  filename   = "./zips/new_boto3.zip"
  layer_name = "updated_boto3_lambda_layer"
  compatible_runtimes = ["python3.6", "python3.7", "python3.8","python3.9" ]
}


resource "aws_iam_role" "lambda-role" {
  name = "Subnet-deploy-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name = "subnet-deploy-lambda-role-inline-policy"

    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Action": ["ec2:CreateSubnet","ec2:DescribeSubnets","ec2:ModifySubnetAttribute","ec2:CreateTags","ec2:DeleteTags"],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": "logs:CreateLogGroup",
              "Resource": join("", ["arn:aws:logs:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":*"])
          },
          {
              "Effect": "Allow",
              "Action": [
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
              ],
              "Resource": [
                  join("", ["arn:aws:logs:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":", "log-group:/aws/lambda/v6onlysubnet:*"])
              ]
          }
      ]
    })
  }
}


resource "aws_lambda_function" "create-v6subnet-lambda" {
  function_name = "create-v6only-subnet"
  role          = aws_iam_role.lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  filename         = "./zips/lambda.zip"
  source_code_hash = filebase64sha256("./zips/lambda.zip")
  layers = [aws_lambda_layer_version.boto3_lambda_layer.arn]
  runtime = "python3.8"
  memory_size = 128
  timeout = 10
}


locals {
  lambda_input = {
    az = data.aws_availability_zones.AZs.names[0]
    vpcid   = aws_vpc.RadLabVPC.id
    v6cidr = cidrsubnet(aws_vpc.RadLabVPC.ipv6_cidr_block, 8, 1)
  }
}


data "aws_lambda_invocation" "deploy_v6_subnet" {
  function_name = aws_lambda_function.create-v6subnet-lambda.function_name
  input = jsonencode(local.lambda_input)
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.RadLabVPC.id
  tags = {
    Name = join("", ["IGW-", var.DeploymentName])
  }
}


resource "aws_eip" "natgw_ip" {
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = join("", ["NATGW-IP-", var.DeploymentName])
  }
}


resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.natgw_ip.id
  subnet_id     = aws_subnet.Pub-Dual-Subnet.id
  depends_on    = [aws_internet_gateway.igw, aws_eip.natgw_ip ]
  tags = {
    Name = join("", ["NATGW-", var.DeploymentName])
  }
}


resource "aws_egress_only_internet_gateway" "egw" {
  vpc_id = aws_vpc.RadLabVPC.id
  tags = {
    Name = join("", ["EIGW-", var.DeploymentName])
  }
}


resource "aws_route_table" "PubRoute" {
   vpc_id = aws_vpc.RadLabVPC.id
   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.igw.id
   }
   route {
     ipv6_cidr_block = "::/0"
     gateway_id      = aws_internet_gateway.igw.id
   }
   tags = {
     Name = join("", [var.DeploymentName, "-PubRTable"])
   }
}


resource "aws_route_table" "PrivRoute" {
   depends_on = [aws_nat_gateway.natgw]
   vpc_id = aws_vpc.RadLabVPC.id
   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_nat_gateway.natgw.id
   }
   route {
     ipv6_cidr_block = "::/0"
     gateway_id      = aws_egress_only_internet_gateway.egw.id
   }
   route {
     ipv6_cidr_block = "64:ff9b::/96"
     gateway_id      = aws_nat_gateway.natgw.id
   }
   tags = {
     Name = join("", [var.DeploymentName, "-PrivRTable"])
   }
}


resource "aws_route_table_association" "PubAssociation" {
  subnet_id      = aws_subnet.Pub-Dual-Subnet.id
  route_table_id = aws_route_table.PubRoute.id
}


resource "aws_route_table_association" "PrivAssociation" {
  subnet_id      = replace (data.aws_lambda_invocation.deploy_v6_subnet.result,"\"","")
  route_table_id = aws_route_table.PrivRoute.id
}
