# Argo CD & Tekton Preview Environment Demo

This project demonstrates how to set up automated preview environments for GitHub pull requests using Argo CD ApplicationSets and Tekton CI/CD pipelines.

## Overview

The goal of this project is to automatically:
1.  Trigger a Tekton pipeline upon a GitHub Pull Request event (e.g., opening, synchronizing).
2.  Build a container image for the code in the pull request using Kaniko.
3.  Push the container image to a registry.
4.  Deploy a dedicated preview environment for the pull request using Argo CD.
5.  Update the GitHub pull request status with the build progress and links.

This allows developers and reviewers to test changes in an isolated environment before merging.

## Components

* **Argo CD:** Used for GitOps-style continuous deployment. It manages the Tekton installation, the CI pipeline resources, and the preview environments via ApplicationSets.
* **Argo CD ApplicationSet:** Specifically, the `pullRequest` generator is used to automatically detect pull requests in a specified GitHub repository (`docker-hello-world` in this demo) and generate Argo CD Applications for preview environments.
* **Tekton Pipelines:** Defines the CI pipeline (`pipeline-build-push-status`) responsible for cloning, building, pushing, and setting GitHub status.
* **Tekton Triggers:** Listens for GitHub webhook events (`github-listener`), extracts relevant data (`github-binding`), and triggers the Tekton pipeline (`github-template`).
* **Tekton Tasks:** Reusable tasks for `git-clone`, `kaniko` (image building), and `github-set-status`.
* **Helm Charts:**
    * `charts/tekton-ci-pipelines`: Deploys necessary Tekton Triggers resources (EventListener, TriggerBinding, TriggerTemplate, RBAC, Secrets) and the Tekton Pipeline definition.
    * `preview-env-helm`: A simple chart used by the Argo CD ApplicationSet to deploy the application (e.g., `docker-hello-world`) into the preview environment namespace.

## Workflow

1.  A developer opens or updates a Pull Request in the configured GitHub repository (`badaiv/docker-hello-world` as per `appset.yaml`).
2.  GitHub sends a webhook event to the publicly exposed Tekton EventListener URL (configured via ngrok).
3.  The EventListener (`github-listener`), using interceptors (GitHub validation, CEL filter), verifies the event and extracts data using the `github-binding`.
4.  The `github-template` triggers the `pipeline-build-push-status` PipelineRun.
5.  The pipeline:
    * Sets the GitHub status to pending.
    * Clones the repository branch associated with the PR.
    * Builds the Docker image using Kaniko and the checked-out code.
    * Pushes the image to a Docker container registry (implicitly via Kaniko, requires docker config secret). The image is tagged with the commit SHA (`{{head_sha}}`).
    * Updates the GitHub status to success or failure.
6.  Simultaneously, the Argo CD ApplicationSet controller detects the open Pull Request.
7.  It generates an Argo CD Application based on the `template` section in `appset.yaml`.
8.  This Application uses the `preview-env-helm` chart to deploy the application.
9.  The deployment uses the image built by Tekton, identified by the commit SHA (`version: '{{head_sha}}'`).
10. The application is deployed into a unique namespace for the branch (`env-preview-docker-hello-world-{{branch}}`).

## Directory Structure
```
├── argocd/                 # Argo CD bootstrap, applications, and appsets
│   ├── apps/               # Argo CD Application definitions (Tekton, CI Pipelines)
│   ├── appsets/            # Argo CD ApplicationSet definitions (PR generator, secrets)
│   └── install/            # Argo CD Helm installation values
├── charts/                 # Helm charts
│   └── tekton-ci-pipelines/ # Helm chart for Tekton CI resources
├── preview-env-helm/       # Helm chart for the preview application deployment
├── scripts/                # Utility scripts
│   └── port_forward_services.sh # Script to port-forward Argo CD/Tekton UIs
├── tekton/                 # Base Tekton installation YAMLs (Pipelines, Triggers, Dashboard)
├── bootstrap.sh            # Main bootstrap script for Argo CD and Tekton setup
└── clean.sh                # Script to clean up the minikube environment
```

## Setup & Usage

### Prerequisites

Setup was done on local MacOS with the following tools:

* Docker Desktop
* Kubernetes cluster (was tested with Minikube)
* `kubectl` configured to access your cluster
* `helm` v3+ installed
* `ngrok` or a similar tunneling tool installed
```shell
brew install minikube kubectl helm ngrok
```

### Configuration

1.  **GitHub Token:** Create a GitHub Personal Access Token (PAT) with appropriate permissions (e.g., `repo`, `admin:repo_hook`). Update the placeholder token in:
    * `argocd/appsets/github-token.yaml`
    * `charts/tekton-ci-pipelines/values.yaml`
2.  **GitHub Webhook Secret:** Choose a secret string for webhook validation. Update the placeholder secret in:
    * `charts/tekton-ci-pipelines/values.yaml` 
    * You will configure this same secret in your GitHub repository's webhook settings later.
3.  **Docker Credentials:** Provide base64 encoded Docker `config.json` credentials for pushing images. Update the placeholder in:
    * `charts/tekton-ci-pipelines/values.yaml`


### Installation

1.  **Start Minikube (if using):**
    ```bash
    minikube start --driver=docker
    ```
2.  **Run Bootstrap Script:** This will install Argo CD and apply the necessary Argo CD Applications/ApplicationSets.
    ```bash
    ./bootstrap.sh
    ```
    This script handles:
    * Adding the Argo Helm repo.
    * Installing/Upgrading Argo CD using Helm with values from `argocd/install/argocd-values.yaml`.
    * Applying the Tekton Application (`argocd/apps/tekton-app.yaml`) which installs Tekton Pipelines, Triggers, and Dashboard.
    * Applying the GitHub token Secret (`argocd/appsets/github-token.yaml`).
    * Applying the ApplicationSet (`argocd/appsets/appset.yaml`).
    * Applying the Tekton CI Pipelines Application (`argocd/apps/tekton-ci-pipelines.yaml`) which deploys the CI pipeline via the Helm chart.

### Exposing the EventListener for GitHub Webhooks

The Tekton EventListener needs to be accessible from the public internet for GitHub to send webhook events.

1.  **Forward the EventListener Service:** Run the port-forwarding script in a terminal. This forwards the `el-github-listener` service (in the `ci-pipelines` namespace) to `localhost:8888` among other services. Keep this script running.
    ```bash
    ./scripts/port_forward_services.sh
    port_forward_services
    ```
2.  **Expose with ngrok:** In a *separate* terminal, use `ngrok` to expose the locally forwarded port (8888) to the internet.
    ```bash
    ngrok http 8888
    ```
3.  **Configure GitHub Webhook:**
    * Ngrok will display a public HTTPS URL (e.g., `https://<random-string>.ngrok.io`). Copy this URL.
    * Go to your target GitHub repository (`badaiv/docker-hello-world` or the one you configured).
    * Navigate to `Settings` > `Webhooks` > `Add webhook`.
    * Paste the ngrok HTTPS URL into the **Payload URL** field.
    * Change the **Content type** to `application/json`.
    * Enter the **Secret** you configured in `charts/tekton-ci-pipelines/values.yaml` (Step 2 of Configuration).
    * Under "Which events would you like to trigger this webhook?", select `Let me select individual events.` and check **Pull requests**.
    * Ensure the webhook is **Active**.
    * Click **Add webhook**.

### Triggering the Workflow

1.  Open a Pull Request (or push an update to an existing one) in the GitHub repository configured in `argocd/appsets/appset.yaml`.
2.  Observe the Tekton PipelineRun being created in the `ci-pipelines` namespace (check Tekton Dashboard).
3.  Observe the Argo CD Application being created for the PR (e.g., `docker-hello-world-<branch>-<pr-number>`) (check Argo CD UI).
4.  Observe the preview environment being deployed in the corresponding namespace (e.g., `env-preview-docker-hello-world-<branch>`).

### Accessing Services

The `port_forward_services` function (which should still be running for the webhook) forwards:
* Argo CD UI: `http://localhost:8080` (default)
* Tekton Dashboard: `http://localhost:9097` (default)
* Tekton EventListener: `http://localhost:8888` (default, forwarded locally; exposed publicly via ngrok for GitHub webhooks)

Login to Argo CD using the username `admin` and the password printed during the `./bootstrap.sh` execution.

### Cleanup

`./clean.sh` - will delete minikube and start from scratch.

