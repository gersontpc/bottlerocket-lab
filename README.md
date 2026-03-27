# bottlerocket-lab
Bottlerocket

## Amazon EKS MCP Server Integration

This cluster is integrated with the [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) (`awslabs.eks-mcp-server`), enabling AI code assistants (Kiro, Cursor, VS Code, etc.) to generate insights and manage the platform through natural language.

### How it works

The EKS MCP Server runs **locally on your machine** and connects to the EKS cluster via the AWS APIs. It exposes cluster state, logs, events, and management capabilities to your AI assistant.

```
Your AI Assistant  ──►  EKS MCP Server (local)  ──►  AWS EKS APIs  ──►  bottlerocket-lab cluster
```

### Prerequisites

- Python 3.10+ and [`uv`](https://docs.astral.sh/uv/getting-started/installation/) installed
- AWS CLI configured with credentials
- Your IAM user/role must have the **`bottlerocket-lab-eks-mcp-server`** policy attached (output from Terraform: `eks_mcp_server_policy_arn`)
- Your IAM principal must have an EKS Access Entry on the cluster (the cluster creator already has admin access; others can be added via the `aws_eks_access_entry` resource)

### Setup

1. **Attach the IAM policy** to your IAM user or role:
   ```bash
   # Retrieve the policy ARN from Terraform output
   cd cluster
   terraform output eks_mcp_server_policy_arn

   # Attach it to your IAM identity
   aws iam attach-user-policy \
     --user-name <YOUR_IAM_USER> \
     --policy-arn <POLICY_ARN>
   ```

2. **Configure your kubeconfig** so the MCP server can reach the cluster:
   ```bash
   $(terraform output -raw configure_kubectl)
   ```

3. **Configure your AI assistant** using one of the options below.

### AI Assistant Configuration

#### Kiro IDE

The repository already ships a ready-to-use config at `.kiro/settings/mcp.json`. Open the project in Kiro and it will be picked up automatically. You can also install it with a single click:

> **Note:** `AWS_REGION` in `.kiro/settings/mcp.json` defaults to `us-east-1`. Update it to match the region used for your cluster (i.e., `var.aws_region`).

[![Add to Kiro](https://kiro.dev/images/add-to-kiro.svg)](https://kiro.dev/launch/mcp/add?name=awslabs.eks-mcp-server&config=%7B%22command%22%3A%22uvx%22%2C%22args%22%3A%5B%22awslabs.eks-mcp-server%40latest%22%2C%22--allow-write%22%2C%22--allow-sensitive-data-access%22%5D%2C%22env%22%3A%7B%22FASTMCP_LOG_LEVEL%22%3A%22ERROR%22%7D%7D)

#### Cursor

[![Install MCP Server](https://cursor.com/deeplink/mcp-install-light.svg)](https://cursor.com/en/install-mcp?name=awslabs.eks-mcp-server&config=eyJhdXRvQXBwcm92ZSI6W10sImRpc2FibGVkIjpmYWxzZSwiY29tbWFuZCI6InV2eCBhd3NsYWJzLmVrcy1tY3Atc2VydmVyQGxhdGVzdCAtLWFsbG93LXdyaXRlIC0tYWxsb3ctc2Vuc2l0aXZlLWRhdGEtYWNjZXNzIiwiZW52Ijp7IkZBU1RNQ1BfTE9HX0xFVkVMIjoiRVJST1IifSwidHJhbnNwb3J0VHlwZSI6InN0ZGlvIn0%3D)

Or add to `~/.cursor/mcp.json` (replace `us-east-1` with your cluster region):

```json
{
  "mcpServers": {
    "awslabs.eks-mcp-server": {
      "command": "uvx",
      "args": [
        "awslabs.eks-mcp-server@latest",
        "--allow-write",
        "--allow-sensitive-data-access"
      ],
      "env": {
        "AWS_REGION": "us-east-1",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

#### VS Code

The repository ships a ready-to-use project-scoped config at `.vscode/mcp.json`. Open the project folder in VS Code and the MCP server will be available immediately in GitHub Copilot Chat (agent mode).

> **Note:** `AWS_REGION` in `.vscode/mcp.json` defaults to `us-east-1`. Update it to match the region used for your cluster (i.e., `var.aws_region`).

**Requirements:** VS Code 1.99+ with the [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension (or any MCP-compatible extension).

You can also install it with a single click:

[![Install on VS Code](https://img.shields.io/badge/Install_on-VS_Code-FF9900?style=flat-square&logo=visualstudiocode&logoColor=white)](https://insiders.vscode.dev/redirect/mcp/install?name=EKS%20MCP%20Server&config=%7B%22autoApprove%22%3A%5B%5D%2C%22disabled%22%3Afalse%2C%22command%22%3A%22uvx%22%2C%22args%22%3A%5B%22awslabs.eks-mcp-server%40latest%22%2C%22--allow-write%22%2C%22--allow-sensitive-data-access%22%5D%2C%22env%22%3A%7B%22FASTMCP_LOG_LEVEL%22%3A%22ERROR%22%7D%2C%22transportType%22%3A%22stdio%22%7D)

Or configure manually: add the following to `.vscode/mcp.json` in the project root (replace `us-east-1` with your cluster region):

```json
{
  "servers": {
    "awslabs.eks-mcp-server": {
      "type": "stdio",
      "command": "uvx",
      "args": [
        "awslabs.eks-mcp-server@latest",
        "--allow-write",
        "--allow-sensitive-data-access"
      ],
      "env": {
        "AWS_REGION": "us-east-1",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

To verify the server is running, open the Copilot Chat panel, switch to **Agent** mode, and type `@awslabs.eks-mcp-server /tools` — you should see the list of available EKS tools.

### What the EKS MCP Server can do

| Capability | Example prompt |
|---|---|
| Describe cluster state | "What is the health status of the bottlerocket-lab cluster?" |
| List/inspect workloads | "Show me all pods in the `app` namespace and their status" |
| View logs & events | "Get the last 100 lines of logs from the nginx pod" |
| Troubleshoot issues | "Why is the nginx deployment not scaling?" |
| Apply manifests | "Deploy the manifest in `app/nginx-deployment.yaml`" |
| Generate manifests | "Generate a deployment manifest for a Redis cache with 256 Mi memory" |
| Cluster insights | "Are there any EKS upgrade insights or health issues I should know about?" |

### Infrastructure changes made for this integration

| Resource | Purpose |
|---|---|
| `aws_cloudwatch_log_group.eks` | Stores EKS control-plane logs so the MCP server can query them |
| `enabled_cluster_log_types` on `aws_eks_cluster.this` | Sends API, audit, authenticator, controller-manager, and scheduler logs to CloudWatch |
| `aws_iam_policy.eks_mcp_server` | Minimum read permissions required by the MCP server |
| `.kiro/settings/mcp.json` | Ready-to-use MCP configuration for Kiro IDE |
| `.vscode/mcp.json` | Ready-to-use MCP configuration for VS Code (GitHub Copilot agent mode) |
