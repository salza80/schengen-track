FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN dnf install -y git && \
    pip install --no-cache-dir -r requirements.txt && \
    dnf clean all

COPY app.py local_mcp.py ./

CMD ["app.lambda_handler"]
