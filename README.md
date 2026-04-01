# bottlerocket-lab

Laboratório de infraestrutura para provisionar um cluster Amazon EKS com nós Bottlerocket gerenciados pelo Karpenter, controller em Fargate, add-ons essenciais, observabilidade básica e estratégia de atualização via BRUPOP.

## Visão geral

Este repositório usa Terraform para criar e configurar:

- cluster EKS com autenticação via Access Entries
- nós Bottlerocket provisionados por Karpenter
- controller do Karpenter executando em EKS Fargate
- add-ons gerenciados do EKS
- métricas e componentes auxiliares instalados via Helm
- coleta de logs do host Bottlerocket para CloudWatch Logs

O diretório principal da infraestrutura é `cluster/`, enquanto `app/nginx-deployment.yaml` contém um exemplo simples de workload para validação do ambiente.

## Arquitetura resumida

- o control plane do EKS é criado via Terraform
- o Karpenter instala um `EC2NodeClass` Bottlerocket e um `NodePool` padrão
- o `NodePool` padrão usa arquitetura `arm64`, favorecendo instâncias Graviton
- o controller do Karpenter roda em um profile dedicado do EKS Fargate
- os nós Bottlerocket enviam logs do host para o mesmo log group do cluster no CloudWatch
- o BRUPOP é usado para orquestrar atualizações do sistema operacional Bottlerocket

## Estrutura do repositório

- `cluster/`: código Terraform da infraestrutura
- `cluster/templates/`: templates do user data Bottlerocket e da configuração do Fluent Bit
- `cluster/charts/karpenter-resources/`: chart local com `EC2NodeClass` e `NodePool`
- `app/`: workload de exemplo para deploy no cluster
- `.github/workflows/`: workflow manual de provisionamento e deploy

## Pré-requisitos

Para uso local, tenha instalado:

- Terraform `>= 1.9`
- AWS CLI autenticado em uma conta com permissões para EKS, EC2, IAM, CloudWatch e Fargate
- `kubectl` para validação e operação do cluster

Pré-requisitos de ambiente:

- uma VPC existente, por padrão com tag/name `default`
- subnets públicas para o cluster
- subnets privadas para o Fargate, ou permissão para o Terraform criá-las automaticamente

## Provisionamento local

Inicialize e aplique a infraestrutura:

```bash
cd cluster
terraform init
terraform plan
terraform apply
```

Depois, configure o acesso ao cluster:

```bash
aws eks update-kubeconfig --name bottlerocket-lab --region us-east-1
```

Valide os principais recursos:

```bash
kubectl get nodes
kubectl get nodepool,ec2nodeclass -A
kubectl get pods -A
```

Para publicar o app de exemplo:

```bash
kubectl apply -f ../app/nginx-deployment.yaml
kubectl rollout status deployment/nginx -n app
```

## Workflow do GitHub Actions

O workflow manual em `.github/workflows/provision-cluster-and-deploy-app.yml` executa este fluxo:

1. faz `terraform init`, `plan` e `apply` em `cluster/`
2. atualiza o kubeconfig do cluster criado
3. aguarda o rollout do CoreDNS e do Karpenter
4. aguarda o `EC2NodeClass` e o `NodePool` ficarem prontos
5. aplica `app/nginx-deployment.yaml`
6. exibe os recursos principais no final da execução

Autenticação suportada no GitHub Actions:

- recomendada: `AWS_ROLE_ARN` com OIDC
- alternativa: `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`

O workflow está fixado em `us-east-1`, alinhado com o valor padrão de `aws_region` neste repositório.

## Rede, Karpenter e Fargate

O cluster usa subnets públicas para o control plane e para descoberta de rede associada ao EKS, enquanto o controller do Karpenter roda em um profile dedicado do EKS Fargate.

Por padrão, `cluster/network.tf` cria:

- três subnets privadas para Fargate em `us-east-1a`, `us-east-1b` e `us-east-1c`
- um NAT Gateway
- uma route table privada para essas subnets

Se você já possui subnets privadas, defina `fargate_subnet_ids`. Se quiser desabilitar a criação automática desse caminho de rede, use `create_fargate_private_network = false`.

## Bottlerocket e customização do user data

O user data dos nós Bottlerocket fica em `cluster/templates/bottlerocket-user-data.toml.tftpl`.

O Terraform renderiza esse template com `templatefile(...)` e injeta o resultado em `spec.userData` do `EC2NodeClass` gerenciado pelo chart local em `cluster/charts/karpenter-resources/`.

Na prática, esse user data faz duas coisas importantes:

- aplica customizações do sistema Bottlerocket no bootstrap dos nós
- habilita o host container `log-shipper`, baseado em `aws-for-fluent-bit`

## Observabilidade e logs do host

Os logs do control plane do EKS são enviados ao CloudWatch por `enabled_cluster_log_types` no recurso `aws_eks_cluster.this`.

Além disso, os nós Bottlerocket executam um host container de log shipping que:

- lê o journal do host diretamente de `/.bottlerocket/rootfs/var/log/journal`
- usa o output `cloudwatch_logs` do Fluent Bit
- envia os logs para o mesmo log group do cluster
- organiza streams no padrão `bottlerocket-<private-dns>` usando `_HOSTNAME`
- usa `bottlerocket-host` como fallback quando o hostname não pode ser resolvido

A configuração atual usa um único input amplo de journal do host. Isso significa que logs de serviços como `kubelet.service`, `containerd.service`, `host-containerd.service` e `host-containers@log-shipper.service` são enviados juntos para o stream de host.

Os principais controles de segurança operacional do Fluent Bit estão expostos por variáveis Terraform, incluindo:

- `bottlerocket_log_shipper_log_level`
- `bottlerocket_log_shipper_storage_backlog_mem_limit`
- `bottlerocket_log_shipper_input_mem_buf_limit`
- `bottlerocket_log_shipper_storage_max_chunks_up`
- `bottlerocket_log_shipper_output_storage_total_limit_size`
- `bottlerocket_log_shipper_max_entries`
- `bottlerocket_log_shipper_db_sync`

![](./img/bottlerocket-host-container-log.png)

## BRUPOP

O Bottlerocket Update Operator é instalado via Helm e pode ser ajustado por variáveis Terraform, sem edição manual do release.

As variáveis mais relevantes são:

- `brupop_scheduler_cron_expression`
- `brupop_update_window_start`
- `brupop_update_window_stop`
- `brupop_max_concurrent_updates`
- `brupop_exclude_from_lb_wait_time_in_sec`

O padrão atual agenda uma execução diária às `01:00 UTC`, dentro da janela entre `00:00:00` e `02:00:00`.

## Variáveis mais úteis

| Variável | Finalidade |
|---|---|
| `aws_region` | Região AWS do cluster |
| `cluster_name` | Nome do cluster EKS |
| `kubernetes_version` | Versão do Kubernetes |
| `fargate_subnet_ids` | Lista de subnets privadas para Fargate |
| `create_fargate_private_network` | Define se o Terraform cria a rede privada do Fargate |
| `karpenter_bottlerocket_ami_alias` | Alias da AMI Bottlerocket usada pelo `EC2NodeClass` |
| `karpenter_capacity_types` | Tipos de capacidade aceitos pelo NodePool |
| `karpenter_instance_categories` | Categorias de instância EC2 permitidas |
| `karpenter_instance_sizes` | Tamanhos de instância permitidos |
| `karpenter_nodepool_cpu_limit` | Limite agregado de CPU do NodePool |
| `karpenter_nodepool_memory_limit` | Limite agregado de memória do NodePool |
| `cloudwatch_log_retention_days` | Retenção dos logs do control plane |

## Componentes provisionados

| Recurso | Finalidade |
|---|---|
| `aws_cloudwatch_log_group.eks` | Armazena os logs do control plane do EKS |
| `aws_eks_addon.vpc_cni` | Instala o add-on de rede do EKS |
| `aws_eks_addon.kube_proxy` | Instala o kube-proxy gerenciado pelo EKS |
| `aws_eks_addon.coredns` | Instala o CoreDNS gerenciado pelo EKS |
| `aws_eks_addon.pod_identity_agent` | Instala o agente de Pod Identity do EKS |
| `aws_eks_fargate_profile.karpenter` | Executa o controller do Karpenter no Fargate |
| `helm_release.karpenter` | Instala o controller do Karpenter |
| `helm_release.karpenter_resources` | Aplica o `EC2NodeClass` e o `NodePool` |
| `helm_release.metrics_server` | Instala o metrics-server |
| `helm_release.kube_state_metrics` | Instala o kube-state-metrics |
| `helm_release.cert_manager` | Instala o cert-manager |
| `helm_release.bottlerocket_shadow` | Instala o chart CRD do BRUPOP |
| `helm_release.bottlerocket_update_operator` | Instala o Bottlerocket Update Operator |

## Observações importantes

- este repositório não define backend remoto do Terraform
- para uso contínuo em CI, o ideal é armazenar o state em backend compartilhado, como S3 com locking
- os arquivos `.tfstate` não devem ser versionados
- mudanças em `cluster/templates/` impactam diretamente o bootstrap e a observabilidade dos nós Bottlerocket

## Fontes

- [Documentação do Bottlerocket sobre host containers](https://bottlerocket.dev/en/os/1.54.x/api/settings/host-containers/#container_source) (propósito: referência para a configuração e o comportamento de `settings.host-containers.*`, incluindo a origem da imagem do container)
- [README do Bottlerocket Update Operator](https://github.com/bottlerocket-os/bottlerocket-update-operator/blob/develop/README.md) (propósito: documentação operacional e de uso do BRUPOP)
- [Repositório do Bottlerocket Update Operator](https://github.com/bottlerocket-os/bottlerocket-update-operator) (propósito: código-fonte, releases, issues e visão geral do projeto)
