--!strict

type ComponentState = {
	initialDisplacement: number,
	initialVelocity: number,
}

export type SpringConfig = {
	initial: any,
	target: any,
	duration: number,
	bounce: number,
}

export type Spring = {
	dampingRatio: number,
	naturalFrequency: number,
	duration: number,
	bounce: number,
	targetComponents: { number },
	componentStates: { ComponentState },
	elapsedTime: number,
	valueType: string,
	settled: boolean,
	setTarget: (self: Spring, newTarget: any) -> (),
	setDuration: (self: Spring, newDuration: number) -> (),
	setBounce: (self: Spring, newBounce: number) -> (),
	update: (self: Spring, deltaTime: number) -> any,
	getValue: (self: Spring) -> any,
	getVelocity: (self: Spring) -> any,
	isSettled: (self: Spring) -> boolean,
	reset: (self: Spring, position: any) -> (),
	play: (self: Spring, instanceOrCallback: any, property: string?) -> (),
	stop: (self: Spring) -> (),
}

local SETTLING_EPSILON = 0.01
local LOG_EPSILON = -math.log(SETTLING_EPSILON)
local CRITICAL_SETTLING_FACTOR = 6.64
local SETTLED_THRESHOLD = 0.001

local RunService = game:GetService("RunService")

type PlayEntry = {
	spring: any,
	callback: (any) -> (),
}

local activeEntries: { PlayEntry } = {}
local updateConnection: RBXScriptConnection? = nil

local function decomposeValue(value: any): { number }
	local valueType = typeof(value)

	if valueType == "number" then
		return { value :: number }
	elseif valueType == "Vector2" then
		local v = value :: Vector2
		return { v.X, v.Y }
	elseif valueType == "Vector3" then
		local v = value :: Vector3
		return { v.X, v.Y, v.Z }
	elseif valueType == "UDim2" then
		local v = value :: UDim2
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif valueType == "UDim" then
		local v = value :: UDim
		return { v.Scale, v.Offset }
	elseif valueType == "Color3" then
		local v = value :: Color3
		return { v.R, v.G, v.B }
	elseif valueType == "CFrame" then
		local v = value :: CFrame
		local rx, ry, rz = v:ToEulerAnglesXYZ()
		return { v.Position.X, v.Position.Y, v.Position.Z, rx, ry, rz }
	end

	error(`[springs] Unsupported type: {valueType}`)
end

local function composeValue(components: { number }, valueType: string): any
	if valueType == "number" then
		return components[1]
	elseif valueType == "Vector2" then
		return Vector2.new(components[1], components[2])
	elseif valueType == "Vector3" then
		return Vector3.new(components[1], components[2], components[3])
	elseif valueType == "UDim2" then
		return UDim2.new(components[1], components[2], components[3], components[4])
	elseif valueType == "UDim" then
		return UDim.new(components[1], components[2])
	elseif valueType == "Color3" then
		return Color3.new(
			math.clamp(components[1], 0, 1),
			math.clamp(components[2], 0, 1),
			math.clamp(components[3], 0, 1)
		)
	elseif valueType == "CFrame" then
		return CFrame.new(components[1], components[2], components[3])
			* CFrame.Angles(components[4], components[5], components[6])
	end

	error(`[springs] Unsupported type: {valueType}`)
end

local function bounceToDampingRatio(bounce: number): number
	local clampedBounce = math.clamp(bounce, 0, 1)
	return 1.0 - clampedBounce * 0.9
end

local function computeNaturalFrequency(dampingRatio: number, duration: number): number
	if duration <= 0 then
		return 1e4
	end

	if dampingRatio < 0.999 then
		return LOG_EPSILON / (dampingRatio * duration)
	end

	if dampingRatio >= 0.999 and dampingRatio <= 1.001 then
		local underdampedOmega = LOG_EPSILON / (0.999 * duration)
		local criticalOmega = CRITICAL_SETTLING_FACTOR / duration
		local blendFactor = (dampingRatio - 0.999) / 0.002
		blendFactor = math.clamp(blendFactor, 0, 1)
		return underdampedOmega + (criticalOmega - underdampedOmega) * blendFactor
	end

	local discriminant = math.sqrt(dampingRatio * dampingRatio - 1)
	local slowModeFactor = dampingRatio - discriminant
	return LOG_EPSILON / (slowModeFactor * duration)
end

local function solveSpring(
	displacement0: number,
	velocity0: number,
	dampingRatio: number,
	naturalFreq: number,
	time: number
): (number, number)
	if time <= 0 then
		return displacement0, velocity0
	end

	local zeta = dampingRatio
	local omegaN = naturalFreq

	if zeta < 1.0 - 1e-6 then
		local omegaD = omegaN * math.sqrt(1 - zeta * zeta)

		local coeffA = displacement0
		local coeffB = (velocity0 + zeta * omegaN * displacement0) / omegaD

		local expDecay = math.exp(-zeta * omegaN * time)

		local cosComponent = math.cos(omegaD * time)
		local sinComponent = math.sin(omegaD * time)

		local displacement = expDecay * (coeffA * cosComponent + coeffB * sinComponent)

		local velocity = expDecay * (
			(-zeta * omegaN * coeffA + omegaD * coeffB) * cosComponent
			+ (-zeta * omegaN * coeffB - omegaD * coeffA) * sinComponent
		)

		return displacement, velocity

	elseif zeta <= 1.0 + 1e-6 then
		local coeffA = displacement0
		local coeffB = velocity0 + omegaN * displacement0

		local expDecay = math.exp(-omegaN * time)

		local displacement = expDecay * (coeffA + coeffB * time)

		local velocity = expDecay * (coeffB - omegaN * (coeffA + coeffB * time))

		return displacement, velocity

	else
		local discriminant = math.sqrt(zeta * zeta - 1)

		local root1 = omegaN * (-zeta + discriminant)
		local root2 = omegaN * (-zeta - discriminant)

		local rootDiff = root1 - root2
		local coeffA = (velocity0 - root2 * displacement0) / rootDiff
		local coeffB = (root1 * displacement0 - velocity0) / rootDiff

		local exp1 = math.exp(root1 * time)
		local exp2 = math.exp(root2 * time)

		local displacement = coeffA * exp1 + coeffB * exp2

		local velocity = coeffA * root1 * exp1 + coeffB * root2 * exp2

		return displacement, velocity
	end
end

local Springs = {}
Springs.__index = Springs

function Springs.new(config: SpringConfig): Spring
	local valueType = typeof(config.initial)
	assert(valueType == typeof(config.target), `[springs] initial과 target의 타입이 다릅니다: {valueType} vs {typeof(config.target)}`)

	local dampingRatio = bounceToDampingRatio(config.bounce)
	local naturalFrequency = computeNaturalFrequency(dampingRatio, config.duration)

	local initialComponents = decomposeValue(config.initial)
	local targetComponents = decomposeValue(config.target)

	local componentStates: { ComponentState } = {}
	for index = 1, #initialComponents do
		table.insert(componentStates, {
			initialDisplacement = initialComponents[index] - targetComponents[index],
			initialVelocity = 0,
		})
	end

	local self = setmetatable({
		dampingRatio = dampingRatio,
		naturalFrequency = naturalFrequency,
		duration = config.duration,
		bounce = config.bounce,
		targetComponents = targetComponents,
		componentStates = componentStates,
		elapsedTime = 0,
		valueType = valueType,
		settled = false,
	}, Springs)

	return self :: any
end

local function recalculatePhysics(self: Spring)
	local currentComponents: { number } = {}
	local currentVelocities: { number } = {}

	for index, state in self.componentStates do
		local disp, vel = solveSpring(
			state.initialDisplacement,
			state.initialVelocity,
			self.dampingRatio,
			self.naturalFrequency,
			self.elapsedTime
		)
		currentComponents[index] = self.targetComponents[index] + disp
		currentVelocities[index] = vel
	end

	self.dampingRatio = bounceToDampingRatio(self.bounce)
	self.naturalFrequency = computeNaturalFrequency(self.dampingRatio, self.duration)

	for index, state in self.componentStates do
		state.initialDisplacement = currentComponents[index] - self.targetComponents[index]
		state.initialVelocity = currentVelocities[index]
	end

	self.elapsedTime = 0
	self.settled = false
end

function Springs.setTarget(self: Spring, newTarget: any)
	local newTargetComponents = decomposeValue(newTarget)

	for index, state in self.componentStates do
		local currentDisplacement, currentVelocity = solveSpring(
			state.initialDisplacement,
			state.initialVelocity,
			self.dampingRatio,
			self.naturalFrequency,
			self.elapsedTime
		)

		local currentAbsolutePosition = self.targetComponents[index] + currentDisplacement

		state.initialDisplacement = currentAbsolutePosition - newTargetComponents[index]
		state.initialVelocity = currentVelocity
	end

	self.targetComponents = newTargetComponents
	self.elapsedTime = 0
	self.settled = false
end

function Springs.setDuration(self: Spring, newDuration: number)
	self.duration = math.max(newDuration, 0)
	recalculatePhysics(self)
end

function Springs.setBounce(self: Spring, newBounce: number)
	self.bounce = math.clamp(newBounce, 0, 1)
	recalculatePhysics(self)
end

function Springs.update(self: Spring, deltaTime: number): any
	if self.settled then
		return composeValue(self.targetComponents, self.valueType)
	end

	self.elapsedTime += deltaTime

	local resultComponents: { number } = {}
	local allSettled = true

	for index, state in self.componentStates do
		local displacement, velocity = solveSpring(
			state.initialDisplacement,
			state.initialVelocity,
			self.dampingRatio,
			self.naturalFrequency,
			self.elapsedTime
		)

		resultComponents[index] = self.targetComponents[index] + displacement

		if math.abs(displacement) > SETTLED_THRESHOLD or math.abs(velocity) > SETTLED_THRESHOLD then
			allSettled = false
		end
	end

	self.settled = allSettled

	return composeValue(resultComponents, self.valueType)
end

function Springs.getValue(self: Spring): any
	if self.settled then
		return composeValue(self.targetComponents, self.valueType)
	end

	local resultComponents: { number } = {}
	for index, state in self.componentStates do
		local displacement, _ = solveSpring(
			state.initialDisplacement,
			state.initialVelocity,
			self.dampingRatio,
			self.naturalFrequency,
			self.elapsedTime
		)
		resultComponents[index] = self.targetComponents[index] + displacement
	end

	return composeValue(resultComponents, self.valueType)
end

function Springs.getVelocity(self: Spring): any
	if self.settled then
		local zeroComponents: { number } = {}
		for index = 1, #self.targetComponents do
			zeroComponents[index] = 0
		end
		return composeValue(zeroComponents, self.valueType)
	end

	local velocityComponents: { number } = {}
	for index, state in self.componentStates do
		local _, velocity = solveSpring(
			state.initialDisplacement,
			state.initialVelocity,
			self.dampingRatio,
			self.naturalFrequency,
			self.elapsedTime
		)
		velocityComponents[index] = velocity
	end

	return composeValue(velocityComponents, self.valueType)
end

function Springs.isSettled(self: Spring): boolean
	return self.settled
end

function Springs.reset(self: Spring, position: any)
	local positionComponents = decomposeValue(position)

	for index, state in self.componentStates do
		state.initialDisplacement = positionComponents[index] - self.targetComponents[index]
		state.initialVelocity = 0
	end

	self.elapsedTime = 0
	self.settled = false
end

local function ensureUpdateLoop()
	if updateConnection then
		return
	end

	local signal = if RunService:IsClient()
		then RunService.RenderStepped
		else RunService.Heartbeat

	updateConnection = signal:Connect(function(deltaTime: number)
		for _, entry in activeEntries do
			local value = entry.spring:update(deltaTime)
			entry.callback(value)
		end
	end)
end

function Springs.play(self: Spring, instanceOrCallback: any, property: string?)
	self:stop()

	local callback: (any) -> ()

	if typeof(instanceOrCallback) == "function" then
		callback = instanceOrCallback
	else
		assert(property ~= nil, "[springs] 인스턴스를 전달할 때는 속성 이름(property)이 필요합니다.")
		local instance = instanceOrCallback
		local prop = property :: string
		callback = function(value: any)
			(instance :: any)[prop] = value
		end
	end

	table.insert(activeEntries, {
		spring = self,
		callback = callback,
	})

	ensureUpdateLoop()
end

function Springs.stop(self: Spring)
	for index = #activeEntries, 1, -1 do
		if activeEntries[index].spring == self then
			table.remove(activeEntries, index)
		end
	end

	if #activeEntries == 0 and updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
end

return Springs
