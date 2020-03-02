// Copyright 2016 k8s-support Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//////////////////////////////////////////////////////////////////////////////

package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/m-lab/epoxy/extension"
)

type fakeTokenGenerator struct {
	token string
}

func (g *fakeTokenGenerator) Token(target string) ([]byte, error) {
	if g.token == "" {
		return nil, fmt.Errorf("Failing to generate token")
	}
	return []byte(g.token), nil
}

func Test_allocateTokenHandler(t *testing.T) {
	tests := []struct {
		name   string
		method string
		body   string
		v1     *extension.V1
		status int
		token  string
	}{
		{
			name:   "success",
			method: "POST",
			v1: &extension.V1{
				Hostname:    "mlab1.foo01.measurement-lab.org",
				IPv4Address: "192.168.1.1",
				LastBoot:    time.Now().UTC().Add(-5 * time.Minute),
			},
			status: http.StatusOK,
			token:  "012345.abcdefghijklmnop",
		},
		{
			name:   "failure-bad-method",
			method: "GET",
			status: http.StatusMethodNotAllowed,
		},
		{
			name:   "failure-bad-requested",
			method: "POST",
			v1:     nil,
			status: http.StatusBadRequest,
		},
		{
			name:   "failure-last-boot-too-old",
			method: "POST",
			v1: &extension.V1{
				Hostname:    "mlab1.foo01.measurement-lab.org",
				IPv4Address: "192.168.1.1",
				LastBoot:    time.Now().UTC().Add(-125 * time.Minute),
			},
			status: http.StatusRequestTimeout,
		},
		{
			name:   "failure-failure-to-generate-token",
			method: "POST",
			v1: &extension.V1{
				Hostname:    "mlab1.foo01.measurement-lab.org",
				IPv4Address: "192.168.1.1",
				LastBoot:    time.Now().UTC().Add(-5 * time.Minute),
			},
			status: http.StatusInternalServerError,
			token:  "",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			localGenerator = &fakeTokenGenerator{token: tt.token}
			ext := extension.Request{V1: tt.v1}
			req := httptest.NewRequest(
				tt.method, "/allocate_k8s_token", strings.NewReader(ext.Encode()))
			rec := httptest.NewRecorder()

			allocateTokenHandler(rec, req)

			if tt.status != rec.Code {
				t.Errorf("allocateTokenHandler() bad status code: got %d; want %d",
					rec.Code, tt.status)
			}
			if rec.Body.String() != tt.token {
				t.Errorf("allocateTokenHandler() bad token returned: got %q; want %q",
					rec.Body.String(), tt.token)
			}
		})
	}
}

func Test_k8sTokenGenerator_Token(t *testing.T) {
	tests := []struct {
		name     string
		command  string
		response string
	}{
		{
			name:     "success",
			command:  "/bin/echo",
			response: "token create --ttl 5m --description Allow test to join the cluster\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := &k8sTokenGenerator{
				Command: tt.command,
			}
			got, err := g.Token("test")
			if err != nil {
				t.Fatalf("k8sTokenGenerator.Token() = %q, want nil", err)
			}
			if string(got) != tt.response {
				t.Errorf("k8sTokenGenerator.Token() = %q, want %q", got, tt.response)
			}
		})
	}
}
