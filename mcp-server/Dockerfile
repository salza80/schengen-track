FROM public.ecr.aws/lambda/python:3.12

COPY mcp-server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY mcp-server/app.py mcp-server/local_mcp.py ./
COPY src/db/data/countries.xml ./

CMD ["app.lambda_handler"]
