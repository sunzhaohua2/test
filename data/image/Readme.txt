1.stage 环境遇到如下问题：
Failed to pull image "registry.redhat.io/openshift4/ose-cluster-kube-descheduler-operator@sha256:3bfd11efd5188437431e4d78364023f342851a1da5ec6c7c5f52bf23e436e5b6": rpc error: code = Unknown desc = Error reading manifest 
registry.redhat.io/openshift4/ose-cluster-kube-descheduler-operator@sha256:3bfd11efd5188437431e4d78364023f342851a1da5ec6c7c5f52bf23e436e5b6
404 Not found

办法：Create a icsp from registry.stage.redhat.io to registry.redhat.io
oc create -f image-policy-stage-ImageContentSourcePolicy.yaml

2.disconnected env mirror image, upgrade to 4.4.33-x86_64
1)trust the CA that signed the cert for the registry
download https://gitlab.cee.redhat.com/aosqe/flexy-templates/-/raw/master/functionality-testing/certs/generate_ssl_certs/intermediate/certs/ca-chain.cert.pem
# cp ca-chain.cert.pem /etc/pki/ca-trust/source/anchors/
# update-ca-trust

taget_build_arrx=4.4.33-x86_64
cat config.json.template.e | base64 -d > tmpconfig
mirrorRegistry=$(oc get ImageContentSourcePolicy image-policy-0 -o yaml | grep ":5000" | awk '{print $2}' | awk -F"/" '{print $1}')
echo "mirrorRegistry is $mirrorRegistry"
sed -i "s/localregistry/$mirrorRegistry/g" tmpconfig
sed -i "s/tagetbuild/$taget_build_arrx/g" tmpconfig

$ oc extract secret/pull-secret -n openshift-config  --confirm
.dockerconfigjson

Note: if you want to docker login to mirror registry,its username/password is dummy/dummy 
 -a ~/.docker/config.json
-a ./.dockerconfigjson

2)如果upgrade到nightly build
 oc adm release mirror -a ${tmpconfig} --from=registry.ci.openshift.org/ocp/release:${taget_build_arrx} --to=$mirrorRegistry/openshift-release-dev/ocp-release --to-release-image=$mirrorRegistry/openshift-release-dev/ocp-release:${taget_build_arrx}
如果upgrade  to stable build
    oc adm release mirror -a tmpconfig --from=quay.io/openshift-release-dev/ocp-release:${taget_build_arrx} --to=$mirrorRegistry/openshift-release-dev/ocp-release --to-release-image=$mirrorRegistry/openshift-release-dev/ocp-release:${taget_build_arrx} 

3)apply ICSP
./oc apply -f -<<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - $mirrorRegistry/openshift-release-dev/ocp-release
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  - mirrors:
    - $mirrorRegistry/openshift-release-dev/ocp-release
    source: registry.svc.ci.openshift.org/ocp/release
EOF

4) upgrade
oc adm upgrade --to-image=$mirrorRegistry/openshift-release-dev/ocp-release:${taget_build_arrx}  --force=true --allow-explicit-upgrade=true
