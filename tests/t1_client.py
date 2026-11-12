# T1: a normal MCP client (official Python SDK) through CloudFront.
# Run: uv run --with 'mcp==1.30.0' python tests/t1_client.py   (after `source tests/env.sh`)
import asyncio, os
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

async def main():
    headers = {"Authorization": f"Bearer {os.environ['TOKEN']}"}
    async with streamablehttp_client(os.environ["EDGE_URL"], headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print([t.name for t in tools.tools])
            print(await session.call_tool("lookup_order", {"order_id": "A1001"}))

asyncio.run(main())
