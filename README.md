# [Intric](https://intric.ai/en)

## 📋 Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Persistent volume provisioner
  - Run `kubectl get storageclass` to see if you already have one
- Device limits
  - Minimum: 4 CPU cores, 8GB RAM, 1TB storage
  - Preferred for long-term usage or for large userbases: 6 CPU cores, 16GB, 2TB storage
- [Recommended] [Cluster Issuer or Issuer](https://cert-manager.io/docs/concepts/issuer/)
  - Run `kubectl get ClusterIssuer` to see if you already have one
    - There are a lot of ways like [these](https://cert-manager.io/docs/getting-started/) to set one up
  - Without this, you'll have to manually create and manage your tls certificates


## 🚀 Quick Start

- [Recommended] Create a namespace for the resources
  - `kubectl create namespace intric`
- You will be given a values-override.yaml file. Alter it as needed.
  - You can search for `REPLACE_THIS` to see fields that crucially need to be replaced
- [If manually creating tls certificates]: Manually create the tls certificates
  - Refer to the [Domain Configuration] section of the values-override.yaml
- Install the chart
  - `helm install intric KEIII-REPLACE-THIS-AFTER-THE-CI-STUFF -n intric -f ./values-override.yaml`
- Get a Personal Access Token from Zitadel
  - visit your instantiated zitadel host
  - login
    - if using the bundled self-hosted zitadel:
      - credentials for the login user can be found in zitadel.firstInstance.admin of the values-overrides.yaml file
  - create a PAT token
    - head to the users tab
    - go to "service users"
    - click on the one and only user
    - go to "Personal Access Tokens"
    - click on "New"
    - copy the created PAT
- Setup the base zitadel resources
  - `./setup-zitadel-resources.sh --pat INSERT_PAT_HERE --overrideFileIn ./values-override.yaml --overrideFileOut ./modified-values-override.yaml`
  - This will generate a new override file with the Zitadel configuration from the new resources
- Upgrade helm to use the generated Zitadel resources
  - `helm upgrade intric KEIII-REPLACE-THIS-AFTER-THE-CI-STUFF -n intric -f ./modified-values-override.yaml`
- Create the first admin user in Intric
  - `./create-first-admin.sh --overrideFile ./modified-values-override.yaml --zitadelPat INSERT_PAT_HERE`
- ✅ Done

Note:
- if you're using the bundled self-hosted zitadel, you will want to set it up with things like smtp and other supported login methods
```

## 🗑️ Uninstalling
`helm uninstall intric -n INSERT_NAMESPACE_HERE && kubectl delete pvc --all -n INSERT_NAMESPACE_HERE`
