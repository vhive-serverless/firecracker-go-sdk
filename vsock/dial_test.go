// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License"). You may
// not use this file except in compliance with the License. A copy of the
// License is located at
//
//	http://aws.amazon.com/apache2.0/
//
// or in the "license" file accompanying this file. This file is distributed
// on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
// express or implied. See the License for the specific language governing
// permissions and limitations under the License.

package vsock

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTemporaryNetErr(t *testing.T) {
	assert.True(t, isTemporaryNetErr(&ackError{cause: errors.New("ack")}))

	assert.False(t, isTemporaryNetErr(&connectMsgError{cause: errors.New("connect")}))
	assert.False(t, isTemporaryNetErr(errors.New("something else")))
	assert.False(t, isTemporaryNetErr(nil))
}

// The guest may send its first protocol frame immediately after accepting. A
// single host read can therefore contain both the Firecracker ACK and that frame.
func TestTryConnReadUntilPreservesFollowingBytes(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	payload := bytes.Repeat([]byte{0x46, 0x43, 0x49, 0x4f}, 16)
	done := make(chan error, 1)
	go func() {
		_, err := server.Write(append([]byte("OK 12345\n"), payload...))
		_ = server.Close()
		done <- err
	}()
	ack, err := tryConnReadUntil(client, '\n', time.Second)
	require.NoError(t, err)
	require.Equal(t, "OK 12345\n", ack)
	received, err := io.ReadAll(client)
	require.NoError(t, err)
	require.Equal(t, payload, received, "the ACK reader must leave the first protocol frame on the connection")
	require.NoError(t, <-done)
}

func TestDialContextPreservesFollowingBytes(t *testing.T) {
	path := filepath.Join(t.TempDir(), "vsock.sock")
	listener, err := net.Listen("unix", path)
	require.NoError(t, err)
	defer listener.Close()
	payload := bytes.Repeat([]byte{0x46, 0x43, 0x49, 0x4f}, 16)
	done := make(chan error, 1)
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			done <- acceptErr
			return
		}
		defer conn.Close()
		request := make([]byte, len("CONNECT 123\n"))
		if _, readErr := io.ReadFull(conn, request); readErr != nil {
			done <- readErr
			return
		}
		if string(request) != "CONNECT 123\n" {
			done <- errors.New("unexpected CONNECT request")
			return
		}
		_, writeErr := conn.Write(append([]byte("OK 12345\n"), payload...))
		done <- writeErr
	}()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	conn, err := DialContext(ctx, path, 123, WithRetryInterval(time.Millisecond))
	require.NoError(t, err)
	defer conn.Close()
	require.NoError(t, conn.SetReadDeadline(time.Now().Add(time.Second)))
	received, err := io.ReadAll(conn)
	require.NoError(t, err)
	require.Equal(t, payload, received)
	require.NoError(t, <-done)
}

func TestTryConnReadUntilBoundsACK(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() { _, _ = io.WriteString(server, strings.Repeat("x", 33)) }()
	ack, err := tryConnReadUntil(client, '\n', time.Second)
	require.ErrorContains(t, err, "exceeds")
	require.Len(t, ack, 32)
}

func TestTryConnReadUntilTimeoutClearsDeadline(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	_, err := tryConnReadUntil(client, '\n', 20*time.Millisecond)
	var networkErr net.Error
	require.ErrorAs(t, err, &networkErr)
	require.True(t, networkErr.Timeout())
	go func() { _, _ = io.WriteString(server, "next") }()
	received := make([]byte, 4)
	_, err = io.ReadFull(client, received)
	require.NoError(t, err, "the handshake deadline must be cleared after failure")
	require.Equal(t, "next", string(received))
}

func TestTryConnReadUntilIncompleteACK(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		_, _ = io.WriteString(server, "OK 123")
		_ = server.Close()
	}()
	ack, err := tryConnReadUntil(client, '\n', time.Second)
	require.ErrorIs(t, err, io.EOF)
	require.Equal(t, "OK 123", ack)
}
