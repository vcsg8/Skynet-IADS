do
--this class is currently used for AWACS and Ships, at a latter date a separate class for ships could be created, currently not needed
SkynetIADSAWACSRadar = {}
SkynetIADSAWACSRadar = inheritsFrom(SkynetIADSAbstractRadarElement)

function SkynetIADSAWACSRadar:create(radarUnit, iads)
	local instance = self:superClass():create(radarUnit, iads)
	setmetatable(instance, self)
	self.__index = self
	instance.lastUpdatePosition = nil
	instance.natoName = radarUnit:getTypeName()
	return instance
end

function SkynetIADSAWACSRadar:setupElements()
	local unit = self:getDCSRepresentation()
	local radar = SkynetIADSSAMSearchRadar:create(unit)
	radar:setupRangeData()
	table.insert(self.searchRadars, radar)
end


-- AWACs will not scan for HARMS
function SkynetIADSAWACSRadar:scanForHarms()
	
end

function SkynetIADSAWACSRadar:getMaxAllowedMovementForAutonomousUpdateInNM()
	--local radarRange = mist.utils.metersToNM(self.searchRadars[1]:getMaxRangeFindingTarget())
	--return mist.utils.round(radarRange / 10)
	--fixed to 10 nm miles to better fit small SAM sites
	return 10
end

function SkynetIADSAWACSRadar:isUpdateOfAutonomousStateOfSAMSitesRequired()
	local isUpdateRequired = self:getDistanceTraveledSinceLastUpdate() > self:getMaxAllowedMovementForAutonomousUpdateInNM()
	if isUpdateRequired then
		self.lastUpdatePosition = nil
	end
	return isUpdateRequired
end

function SkynetIADSAWACSRadar:getDistanceTraveledSinceLastUpdate()
	local currentPosition = nil
	local dcsRep = self:getDCSRepresentation()
	if dcsRep and dcsRep:isExist() then
		if self.lastUpdatePosition == nil then
			local position = dcsRep:getPosition()
			if position and position.p then
				self.lastUpdatePosition = position.p
			end
		end
		local position = dcsRep:getPosition()
		if position and position.p then
			currentPosition = position.p
		end
	end
	if self.lastUpdatePosition and currentPosition then
		return mist.utils.round(mist.utils.metersToNM(self:getDistanceToUnit(self.lastUpdatePosition, currentPosition)))
	else
		return 0
	end
end

end

