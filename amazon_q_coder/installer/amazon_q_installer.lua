-- Amazon Q Installer for Mudlet
-- Handles installation and configuration of the Amazon Q module

local installer = {}
installer.__index = installer

local logger = require("agent_api.utils").logger

-- Installation steps
local _installSteps = {
    {name = "Checking dependencies", func = installer.checkDependencies},
    {name = "Creating directories", func = installer.createDirectories},
    {name = "Installing CLI", func = installer.installCLI},
    {name = "Configuring module", func = installer.configureModule}
}

-- Check if dependencies are installed
function installer.checkDependencies()
    logger:info("Checking dependencies...")
    
    -- Check if curl is available (for API calls)
    local handle = io.popen("curl --version")
    local result = handle:read("*a")
    handle:close()
    
    if not result or result == "" then
        return false, "curl is not installed"
    end
    
    -- Check if jq is available (for JSON processing)
    handle = io.popen("jq --version")
    result = handle:read("*a")
    handle:close()
    
    if not result or result == "" then
        logger:warn("jq is not installed, JSON processing may be limited")
    end
    
    return true
end

-- Create necessary directories
function installer.createDirectories()
    logger:info("Creating directories...")
    
    local dirs = {
        getMudletHome() .. "/modules/amazon-q",
        getMudletHome() .. "/modules/amazon-q/logs",
        getMudletHome() .. "/modules/amazon-q/config"
    }
    
    for _, dir in ipairs(dirs) do
        if not lfs.attributes(dir) then
            lfs.mkdir(dir)
            logger:debug("Created directory: " .. dir)
        end
    end
    
    return true
end

-- Install Amazon Q CLI
function installer.installCLI()
    logger:info("Installing Amazon Q CLI...")
    
    -- Check if already installed
    local handle = io.popen("amazon-q --version")
    local result = handle:read("*a")
    handle:close()
    
    if result and result ~= "" then
        logger:info("Amazon Q CLI already installed")
        return true
    end
    
    -- Install via npm
    handle = io.popen("npm install -g @aws/amazon-q-cli")
    result = handle:read("*a")
    local success = handle:close()
    
    if not success then
        return false, "Failed to install Amazon Q CLI: " .. result
    end
    
    return true
end

-- Configure the module
function installer.configureModule()
    logger:info("Configuring module...")
    
    local configPath = getMudletHome() .. "/modules/amazon-q/config/config.json"
    local configFile = io.open(configPath, "w")
    
    if not configFile then
        return false, "Failed to create config file"
    end
    
    local defaultConfig = {
        region = "us-east-1",
        logLevel = "info",
        autoStart = true
    }
    
    configFile:write(json.encode(defaultConfig))
    configFile:close()
    
    return true
end

-- Get Mudlet home directory
function getMudletHome()
    return getMudletHomeDir() or (os.getenv("HOME") .. "/.config/mudlet")
end

-- Run the installation
function installer.run()
    logger:info("Starting Amazon Q module installation...")
    
    for _, step in ipairs(_installSteps) do
        logger:info(step.name .. "...")
        local success, err = step.func()
        
        if not success then
            logger:error("Installation failed at " .. step.name .. ": " .. (err or "unknown error"))
            return false, err
        end
        
        logger:info(step.name .. " completed successfully")
    end
    
    logger:info("Installation completed successfully")
    return true
end

return installer