INSTANCE_AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
PROVIDER_ID="aws:///${INSTANCE_AZ}/${INSTANCE_ID}"

mkdir -p patches
cat <<EOF > ./patches/kubeletconfiguration.yaml
providerID: $PROVIDER_ID
EOF

cat ./patches/kubeletconfiguration.yaml

