//AWS Provider
provider "aws" {
        profile = "deepak"
        region = "ap-south-1"
}

//Creating Key-pair
resource "tls_private_key" "tt1_key" {
  algorithm = "RSA"
}

resource "aws_key_pair" "tt1_key_pair" {
   
  depends_on=[tls_private_key.tt1_key]
  
  key_name   = "tt1_key"
  public_key = tls_private_key.tt1_key.public_key_openssh
  
}

//Save Key-pair
resource "local_file" "tt1_key_file" {

  content  = tls_private_key.tt1_key.private_key_pem
  filename = "tt1_key.pem"
  depends_on = [
    tls_private_key.tt1_key
  ]
}

//Creating Security-group
resource "aws_security_group" "tt1_security_group" {

depends_on = [
    aws_key_pair.tt1_key_pair,
  ]
  name        = "tt1_security_group"
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
 
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tt1_security_group"
  }
}

//Webserver Instance
resource "aws_instance" "tt1_web_OS" {
depends_on = [
    aws_security_group.tt1_security_group,

  ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.tt1_key_pair.key_name
  security_groups = [ "tt1_security_group" ]

  provisioner "remote-exec" {
    connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tt1_key.private_key_pem
    host     = aws_instance.tt1_web_OS.public_ip
  }
    inline = [
      "sudo yum install httpd  -y",
	  "sudo yum install php    -y",
	  "sudo yum install git -y",
	  "sudo systemctl start httpd",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "tt1_web_OS"
  }
}

//create EBS storage for webserver
resource "aws_ebs_volume" "tt1_ebs1" {
  availability_zone = aws_instance.tt1_web_OS.availability_zone
  size              = 1

  tags = {
    Name = "tt1_ebs1"
  }
}

//Attaching EBS storage to EC2 Service
resource "aws_volume_attachment" "tt1_ebs1_attach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.tt1_ebs1.id
  instance_id = aws_instance.tt1_web_OS.id
  force_detach = true
}

resource "null_resource" "tt1_mount" {
  depends_on = [
    aws_volume_attachment.tt1_ebs1_attach,
  ]

  connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tt1_key.private_key_pem
    host     = aws_instance.tt1_web_OS.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
	  ]
  }
}  

//create s3 bucket
resource "aws_s3_bucket" "tt1_bucket" {
  bucket = "tt1-bucket1997"
  acl    = "public-read"

  versioning {
    enabled = true
  }
 
  tags = {
    Name = "tt1_bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_public_access_block" "tt1_bucket" {
depends_on=[aws_s3_bucket.tt1_bucket,]
  bucket = aws_s3_bucket.tt1_bucket.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
  
}
// git clone
resource "null_resource" "tt1_image"{
	provisioner "local-exec"{
		command ="git clone https://github.com/deepak10192/hybrid_task1.git  tt1_image"
	}
}


//Create Object using S3 service
resource "aws_s3_bucket_object" "tt1_bucket_object"{
	
	depends_on=[aws_s3_bucket.tt1_bucket,
				null_resource.tt1_image,
	]
	
	bucket=aws_s3_bucket.tt1_bucket.id
	key="front1.png"
	source = "tt1_image/front1.png"
	acl="public-read"
	
}

//create Cloudfront
resource "aws_cloudfront_distribution" "tt1_cloudfront" {
	depends_on=[aws_s3_bucket.tt1_bucket,aws_s3_bucket_public_access_block.tt1_bucket ]
	
    origin {
        domain_name = "tt1-bucket1997.s3.amazonaws.com"
        origin_id = "S3-tt1-bucket1997"

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }
       
	default_root_object = "index.html"
    enabled = true
	 
    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
		
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-tt1-bucket1997"

        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }
 
    restrictions {
        geo_restriction {
           
            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true

    }
}


// Deploy source code from github to webserver
resource "null_resource" "tt1_cloudfront_result" {
  depends_on = [
    aws_cloudfront_distribution.tt1_cloudfront,
	aws_instance.tt1_web_OS,
  ]

  connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tt1_key.private_key_pem
    host     = aws_instance.tt1_web_OS.public_ip
  }
  provisioner "remote-exec" {
    inline = [

      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/deepak10192/hybrid_task1.git /var/www/html",
	  "sudo sed -i 's/Cloudfront/${aws_cloudfront_distribution.tt1_cloudfront.domain_name}/' /var/www/html/index.html",
	  "sudo systemctl restart httpd",
	  "sudo systemctl enable httpd",
	  
	  
    ]
  }
}

//starting website
resource "null_resource" "start_website"  {

depends_on = [
    null_resource.tt1_cloudfront_result,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.tt1_web_OS.public_ip}"
  	}
}