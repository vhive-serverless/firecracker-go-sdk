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

package firecracker

import (
	"context"
	"errors"
	"testing"

	"github.com/firecracker-microvm/firecracker-go-sdk/client/models"
	ops "github.com/firecracker-microvm/firecracker-go-sdk/client/operations"
	"github.com/firecracker-microvm/firecracker-go-sdk/fctesting"
	"github.com/stretchr/testify/require"
)

func TestSnapshotRestoreOverrides(t *testing.T) {
	snapshot := SnapshotConfig{
		MemFilePath: "memory", SnapshotPath: "state", ResumeVM: true,
		NetworkOverrides: []*models.NetworkOverride{{IfaceID: String("eth0"), HostDevName: String("tap-restored")}},
		VsockOverride:    &models.VsockOverride{UdsPath: String("restored.vsock")},
	}
	sentinel := errors.New("snapshot load failed")
	called := false
	mock := fctesting.MockClient{
		LoadSnapshotFn: func(params *ops.LoadSnapshotParams) (*ops.LoadSnapshotNoContent, error) {
			called = true
			require.Equal(t, snapshot.MemFilePath, params.Body.MemFilePath)
			require.Equal(t, snapshot.SnapshotPath, StringValue(params.Body.SnapshotPath))
			require.Equal(t, snapshot.ResumeVM, params.Body.ResumeVM)
			require.Equal(t, snapshot.NetworkOverrides, params.Body.NetworkOverrides)
			require.Equal(t, snapshot.VsockOverride, params.Body.VsockOverride)
			return nil, sentinel
		},
	}
	logger := fctesting.NewLogEntry(t)
	machine := Machine{logger: logger, client: NewClient("", logger, false, WithOpsClient(&mock))}
	require.ErrorIs(t, machine.loadSnapshot(context.Background(), &snapshot), sentinel)
	require.True(t, called)
}

func TestSnapshotRestoreSkipsDeviceCreation(t *testing.T) {
	machine := Machine{Handlers: Handlers{FcInit: defaultFcInitHandlerList}}
	WithSnapshot("memory", "state")(&machine)
	for _, name := range []string{
		AttachDrivesHandlerName, AddVsocksHandlerName, CreateNetworkInterfacesHandlerName,
		CreatePmemHandlerName, CreateSerialHandlerName, CreateMemoryHotplugHandlerName,
	} {
		require.False(t, machine.Handlers.FcInit.Has(name), "restore must not configure device %s before loading state", name)
	}
	require.True(t, machine.Handlers.FcInit.Has(LoadSnapshotHandlerName))
}
