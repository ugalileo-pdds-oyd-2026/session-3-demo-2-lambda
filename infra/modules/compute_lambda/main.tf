resource "aws_iam_role" "lambda" {
  name = "${var.name}-${var.environment}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name}-${var.environment}"
  filename         = "${path.module}/../../../app/app.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../app/app.zip")
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  memory_size      = var.memory_size
  role             = aws_iam_role.lambda.arn

  environment {
    variables = {
      COMPUTE_TYPE = "lambda"
    }
  }
}
