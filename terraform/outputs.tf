output "app_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "app_domain" {
  description = "Domain pointing to the app"
  value       = "https://credpal.webredirect.org"
}
