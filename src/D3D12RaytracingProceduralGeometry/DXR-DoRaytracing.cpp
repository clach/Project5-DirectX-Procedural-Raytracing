#include "stdafx.h"
#include "DXProceduralProject.h"
#include "CompiledShaders\Raytracing.hlsl.h"

using namespace std;
using namespace DX;

// LOOKAT-2.8, DONE-2.8: The final nail in the coffin. This will finalize everything you've done so far.
// This part will tell the GPU all about the nice shader tables you built, the triangle buffers you made and uploaded,
// as well as the acceleration structure you made - and actually tells the GPU to do the raytracing!
void DXProceduralProject::DoRaytracing()
{
	auto commandList = m_deviceResources->GetCommandList();
	auto frameIndex = m_deviceResources->GetCurrentFrameIndex();

	commandList->SetComputeRootSignature(m_raytracingGlobalRootSignature.Get());

	// Copy dynamic buffers to GPU. The dynamic buffers in question are SceneConstant and AABBattributeBuffer.
	// (1) copy the data to the GPU
	// (2) tell the commandList to SetComputeRootShaderResourceView() or SetComputeRootConstantBufferView()
	m_sceneCB.CopyStagingToGpu(frameIndex);
	commandList->SetComputeRootConstantBufferView(GlobalRootSignature::Slot::SceneConstant, m_sceneCB.GpuVirtualAddress(frameIndex));

	// DONE-2.8: do a very similar operation for the m_aabbPrimitiveAttributeBuffer
	m_aabbPrimitiveAttributeBuffer.CopyStagingToGpu(frameIndex);
	commandList->SetComputeRootShaderResourceView(GlobalRootSignature::Slot::AABBattributeBuffer, m_aabbPrimitiveAttributeBuffer.GpuVirtualAddress(frameIndex));

	// Bind the descriptor heaps.
	if (m_raytracingAPI == RaytracingAPI::FallbackLayer)
	{
		m_fallbackCommandList.Get()->SetDescriptorHeaps(1, m_descriptorHeap.GetAddressOf());

	}
	else // DirectX Raytracing
	{
		commandList->SetDescriptorHeaps(1, m_descriptorHeap.GetAddressOf());
	}

	// Bind the acceleration structure.
	if (m_raytracingAPI == RaytracingAPI::FallbackLayer)
	{
		m_fallbackCommandList->SetTopLevelAccelerationStructure(GlobalRootSignature::Slot::AccelerationStructure, m_fallbackTopLevelAccelerationStructurePointer);
	}
	else // DirectX Raytracing
	{
		commandList->SetComputeRootShaderResourceView(GlobalRootSignature::Slot::AccelerationStructure, m_topLevelAS->GetGPUVirtualAddress());
	}

	// DONE-2.8: Bind the Index/Vertex buffer (basically m_indexBuffer. Think about why this isn't m_vertexBuffer too. Hint: CreateRootSignatures() in DXR-Pipeline.cpp.)
	// This should be done by telling the commandList to SetComputeRoot*(). You just have to figure out what * is.
	// Example: in the case of GlobalRootSignature::Slot::SceneConstant above, we used SetComputeRootConstantBufferView()
	// Hint: look at CreateRootSignatures() in DXR-Pipeline.cpp.
	commandList->SetComputeRootDescriptorTable(GlobalRootSignature::Slot::VertexBuffers, m_indexBuffer.gpuDescriptorHandle);

	// DONE-2.8: Bind the OutputView (basically m_raytracingOutputResourceUAVGpuDescriptor). Very similar to the Index/Vertex buffer.
	commandList->SetComputeRootDescriptorTable(GlobalRootSignature::Slot::OutputView, m_raytracingOutputResourceUAVGpuDescriptor);

	// This will define a `DispatchRays` function that takes in a command list, a pipeline state, and a descriptor
	// This will set the hooks using the shader tables built before and call DispatchRays on the command list
	auto DispatchRays = [&](auto* raytracingCommandList, auto* stateObject, auto* dispatchDesc)
	{
		// You will fill in a D3D12_DISPATCH_RAYS_DESC (which is dispatchDesc).
		// DONE-2.8: fill in dispatchDesc->HitGroupTable. Look up the struct D3D12_GPU_VIRTUAL_ADDRESS_RANGE_AND_STRIDE 
		D3D12_GPU_VIRTUAL_ADDRESS_RANGE_AND_STRIDE hitGroupRangeAndStride = {};
		hitGroupRangeAndStride.StartAddress = m_hitGroupShaderTable->GetGPUVirtualAddress();
		hitGroupRangeAndStride.StrideInBytes = m_hitGroupShaderTableStrideInBytes;
		hitGroupRangeAndStride.SizeInBytes = m_hitGroupShaderTable->GetDesc().Width;
		dispatchDesc->HitGroupTable = hitGroupRangeAndStride;

		// DONE-2.8: now fill in dispatchDesc->MissShaderTable
		D3D12_GPU_VIRTUAL_ADDRESS_RANGE_AND_STRIDE missShaderTableRangeAndStride = {};
		missShaderTableRangeAndStride.StartAddress = m_missShaderTable->GetGPUVirtualAddress();
		missShaderTableRangeAndStride.StrideInBytes = m_missShaderTableStrideInBytes;
		missShaderTableRangeAndStride.SizeInBytes = m_missShaderTable->GetDesc().Width;
		dispatchDesc->MissShaderTable = missShaderTableRangeAndStride;

		// DONE-2.8: now fill in dispatchDesc->RayGenerationShaderRecord
		D3D12_GPU_VIRTUAL_ADDRESS_RANGE rayGenShaderRecordRange;
		rayGenShaderRecordRange.StartAddress = m_rayGenShaderTable->GetGPUVirtualAddress();
		rayGenShaderRecordRange.SizeInBytes = m_rayGenShaderTable->GetDesc().Width;
		dispatchDesc->RayGenerationShaderRecord = rayGenShaderRecordRange;

		// We do this for you. This will define how many threads will be dispatched. Basically like a blockDims in CUDA!
		dispatchDesc->Width = m_width;
		dispatchDesc->Height = m_height;
		dispatchDesc->Depth = 1;

		// This will tell the raytracing command list that you created an RTPSO that binds all of this stuff together.
		raytracingCommandList->SetPipelineState1(stateObject);

		// Kick off raytracing
		m_gpuTimers[GpuTimers::Raytracing].Start(commandList);
		raytracingCommandList->DispatchRays(dispatchDesc);
		m_gpuTimers[GpuTimers::Raytracing].Stop(commandList);
	};

	// Use the DispatchRays() function you created.
	D3D12_DISPATCH_RAYS_DESC dispatchDesc = {};
	if (m_raytracingAPI == RaytracingAPI::FallbackLayer)
	{
		DispatchRays(m_fallbackCommandList.Get(), m_fallbackStateObject.Get(), &dispatchDesc);
	}
	else // DirectX Raytracing
	{
		DispatchRays(m_dxrCommandList.Get(), m_dxrStateObject.Get(), &dispatchDesc);
	}
}