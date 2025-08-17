do

SkynetIADSContact = {}
SkynetIADSContact = inheritsFrom(SkynetIADSAbstractDCSObjectWrapper)

SkynetIADSContact.CLIMB = "CLIMB"
SkynetIADSContact.DESCEND = "DESCEND"

SkynetIADSContact.HARM = "HARM"
SkynetIADSContact.NOT_HARM = "NOT_HARM"
SkynetIADSContact.HARM_UNKNOWN = "HARM_UNKNOWN"

function SkynetIADSContact:create(dcsRadarTarget, abstractRadarElementDetected)
	local instance = self:superClass():create(dcsRadarTarget.object)
	setmetatable(instance, self)
	self.__index = self
	instance.abstractRadarElementsDetected = {}
	table.insert(instance.abstractRadarElementsDetected, abstractRadarElementDetected)
	instance.firstContactTime = timer.getAbsTime()
	instance.lastTimeSeen = 0
	instance.dcsRadarTarget = dcsRadarTarget
	local dcsRep = instance:getDCSRepresentation()
	local position = nil
	if dcsRep and dcsRep:isExist() then
		position = dcsRep:getPosition()
	end
	instance.position = position or { p = { x = 0, y = 0, z = 0 } }
	instance.numOfTimesRefreshed = 0
	instance.speed = 0
	instance.harmState = SkynetIADSContact.HARM_UNKNOWN
	instance.simpleAltitudeProfile = {}
	return instance
end

function SkynetIADSContact:setHARMState(state)
	self.harmState = state
end

function SkynetIADSContact:getHARMState()
	return self.harmState
end

function SkynetIADSContact:isIdentifiedAsHARM()
	return self.harmState == SkynetIADSContact.HARM
end

function SkynetIADSContact:isHARMStateUnknown()
	return self.harmState == SkynetIADSContact.HARM_UNKNOWN
end

function SkynetIADSContact:getMagneticHeading()
	if ( self:isExist() ) then
		local dcsRep = self:getDCSRepresentation()
		if dcsRep and dcsRep:isExist() then
			return mist.utils.round(mist.utils.toDegree(mist.getHeading(dcsRep)))
		end
	end
	return -1
end

function SkynetIADSContact:getAbstractRadarElementsDetected()
	return self.abstractRadarElementsDetected
end

function SkynetIADSContact:addAbstractRadarElementDetected(radar)
	self:insertToTableIfNotAlreadyAdded(self.abstractRadarElementsDetected, radar)
end

function SkynetIADSContact:isTypeKnown()
	return self.dcsRadarTarget.type
end

function SkynetIADSContact:isDistanceKnown()
	return self.dcsRadarTarget.distance
end

function SkynetIADSContact:getTypeName()
	if self:isIdentifiedAsHARM() then
		return SkynetIADSContact.HARM
	end
	local dcsRep = self:getDCSRepresentation()
	if dcsRep and dcsRep:isExist() then
		local category = dcsRep:getCategory()
		if category == Object.Category.UNIT then
			return self.typeName
		end
	end
	return "UNKNOWN"
end

function SkynetIADSContact:getPosition()
	return self.position
end

function SkynetIADSContact:getGroundSpeedInKnots(decimals)
	if decimals == nil then
		decimals = 2
	end
	return mist.utils.round(self.speed, decimals)
end

function SkynetIADSContact:getHeightInFeetMSL()
	if self:isExist() then
		local dcsRep = self:getDCSRepresentation()
		if dcsRep then
			local position = dcsRep:getPosition()
			if position and position.p and position.p.y then
				return mist.utils.round(mist.utils.metersToFeet(position.p.y), 0)
			end
		end
	end
	return 0
end

function SkynetIADSContact:getDesc()
	if self:isExist() then
		local dcsRep = self:getDCSRepresentation()
		if dcsRep and dcsRep:isExist() then
			return dcsRep:getDesc()
		end
	end
	return {}
end

function SkynetIADSContact:getNumberOfTimesHitByRadar()
	return self.numOfTimesRefreshed
end

function SkynetIADSContact:refresh()
	if self:isExist() then
		local timeDelta = (timer.getAbsTime() - self.lastTimeSeen)
		if timeDelta > 0 then
			self.numOfTimesRefreshed = self.numOfTimesRefreshed + 1
			local dcsRep = self:getDCSRepresentation()
			if dcsRep then
				local position = dcsRep:getPosition()
				if position and position.p and self.position and self.position.p then
					local distance = mist.utils.metersToNM(mist.utils.get2DDist(self.position.p, position.p))
					local hours = timeDelta / 3600
					self.speed = (distance / hours)
					self:updateSimpleAltitudeProfile()
					self.position = position
				end
			end
		end 
	end
	self.lastTimeSeen = timer.getAbsTime()
end

function SkynetIADSContact:updateSimpleAltitudeProfile()
	local dcsRep = self:getDCSRepresentation()
	if dcsRep then
		local position = dcsRep:getPosition()
		if position and position.p and position.p.y and self.position and self.position.p and self.position.p.y then
			local currentAltitude = position.p.y
			
			local previousPath = ""
			if #self.simpleAltitudeProfile > 0 then
				previousPath = self.simpleAltitudeProfile[#self.simpleAltitudeProfile]
			end
			
			if self.position.p.y > currentAltitude and previousPath ~= SkynetIADSContact.DESCEND then
				table.insert(self.simpleAltitudeProfile, SkynetIADSContact.DESCEND)
			elseif self.position.p.y < currentAltitude and previousPath ~= SkynetIADSContact.CLIMB then
				table.insert(self.simpleAltitudeProfile, SkynetIADSContact.CLIMB)
			end
		end
	end
end

function SkynetIADSContact:getSimpleAltitudeProfile()
	return self.simpleAltitudeProfile
end

function SkynetIADSContact:getAge()
	return mist.utils.round(timer.getAbsTime() - self.lastTimeSeen)
end

end

