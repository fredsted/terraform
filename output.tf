# Public Load Balancers

output "api_address" {
  value = "${aws_elb.backend.dns_name}"
}

output "frontend_address" {
  value = "${aws_elb.frontend.dns_name}"
}

# Private Load Balancers

output "galera_address" {
  value = "${aws_elb.db_mysql.dns_name}"
}