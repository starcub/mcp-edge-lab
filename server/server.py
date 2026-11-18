from mcp.server.fastmcp import FastMCP

mcp = FastMCP(host="0.0.0.0", stateless_http=True)

ORDERS = {"A1001": {"status": "shipped", "total": 42.50}}
BALANCES = {"cust-7": 1830.22}


@mcp.tool()
def lookup_order(order_id: str) -> dict:
    """Look up the status of an order by its ID."""
    return ORDERS.get(order_id, {"error": "order not found"})


@mcp.tool()
def get_account_balance(customer_id: str) -> dict:
    """Return the current account balance for a customer."""
    return {"customer_id": customer_id, "balance": BALANCES.get(customer_id, 0.0)}


@mcp.tool()
def refund_payment(order_id: str, amount: float) -> dict:
    """Refund part or all of an order. This moves real money."""
    return {"order_id": order_id, "refunded": amount, "status": "queued"}


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
