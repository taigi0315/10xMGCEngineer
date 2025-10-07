from fastapi import FastAPI, Query
from pydantic import BaseModel
from typing import List

app = FastAPI()

class QueryRequest(BaseModel):
    text: str


@app.get("/health")
def health():
    return {"status": "ok"}

# POST /query
@app.post("/query")
def query_post(request: QueryRequest):
    return {"received": request.text}

# GET /query
@app.get("/query")
def query_get(
    query: str = Query(..., min_length=1, description="The query to search for")
):
    return {"received": query}
