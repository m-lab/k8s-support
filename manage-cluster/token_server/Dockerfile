FROM golang:1.10
ADD . /go/src/github.com/m-lab/k8s-support/manage-cluster/token_server
RUN go get -v github.com/m-lab/k8s-support/manage-cluster/token_server
ENTRYPOINT ["/go/bin/token_server"]
