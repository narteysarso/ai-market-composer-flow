import FungibleToken from "FungibleToken"
import NonFungibleToken from "NonFungibleToken"
import FlowToken from "FlowToken"

pub contract ModelHub: NonFungibleToken {

    pub let owners: {String: Address}
    pub let nameHashToIDs: {String: UInt64}
    pub let forbiddenChars: String
    pub var totalSupply: UInt64

    pub let ModelStoragePath: StoragePath
    pub let ModelPrivatePath: PrivatePath
    pub let ModelPublicPath: PublicPath

    pub let RegistrarStoragePath: StoragePath
    pub let RegistrarPrivatePath: PrivatePath
    pub let RegistrarPublicPath: PublicPath


    pub event ContractInitialized()
    pub event Deposit(id: UInt64, to : Address?)
    pub event Withdraw(id: UInt64, from: Address?)
    pub event ModelMinted(id: UInt64, name: String, nameHash: String, uri: String, createdAt: UFix64, receiver: Address)
    pub event ModelUpdated(id: UInt64, name: String, nameHash: String, uri: String, updatedAt: UFix64, updator: Address)


    init(){
        self.owners = {}
        self.nameHashToIDs = {}
        self.totalSupply = 0
        self.forbiddenChars = "!@#$%^&*()<>? ./"

        self.ModelStoragePath = StoragePath(identifier: "ModelHubService") ?? panic("Could not set storage path")
        self.ModelPrivatePath = PrivatePath(identifier: "ModelHubService") ?? panic("Could not set private path")
        self.ModelPublicPath = PublicPath(identifier: "ModelHubService") ?? panic("Could not set public path")

        self.RegistrarStoragePath = StoragePath(identifier: "ModelHubServiceRegistrar") ?? panic("Could not set storage path")
        self.RegistrarPrivatePath = PrivatePath(identifier: "ModelHubServiceRegistrar") ?? panic("Could not set private path")
        self.RegistrarPublicPath = PublicPath(identifier: "ModelHubServiceRegistrar") ?? panic("Could not set public path")

        self.account.save(<- self.createEmptyCollection(), to: ModelHub.ModelStoragePath)
        self.account.link<&ModelHub.Collection{NonFungibleToken.CollectionPublic, NonFungibleToken.Receiver, ModelHub.ICollectionPublic}>(self.ModelPublicPath, target: self.ModelStoragePath)
        self.account.link<&ModelHub.Collection>(self.ModelPrivatePath, target: self.ModelStoragePath)

        let collectionCapability = self.account.getCapability<&ModelHub.Collection>(self.ModelPrivatePath)
        let vault <- FlowToken.createEmptyVault()
        let registrar <- create Registrar(vault: <- vault, collection: collectionCapability)
        self.account.save(<- registrar, to: self.RegistrarStoragePath)
        self.account.link<&ModelHub.Registrar{ModelHub.IRegistrarPublic}>(self.RegistrarPublicPath, target: self.RegistrarStoragePath)
        self.account.link<&ModelHub.Registrar>(self.RegistrarPrivatePath, target: self.RegistrarStoragePath)

        emit ContractInitialized()

    }

    pub struct ModelInfo {
        pub let id: UInt64
        pub let owner: Address
        pub let name: String
        pub let nameHash: String
        pub let address: Address?
        pub let bio: String
        pub let uri: String?
        pub let metadata: {String: String}?
        pub let createdAt: UFix64

        init(
            id: UInt64,
            name: String,
            nameHash: String,
            owner: Address,
            address: Address?,
            uri: String?,
            bio: String,
            metadata: {String: String}?,
            createdAt: UFix64,
        ){
            self.id = id
            self.name = name
            self.nameHash = nameHash
            self.createdAt = createdAt
            self.address = address
            self.bio = bio
            self.uri = uri
            self.metadata = metadata
            self.owner = owner
        }
    }

    pub resource interface IModelPublic {
        pub fun getBio() : String
        pub fun getName(): String
        pub fun getAddress(): Address?
    }

    pub resource interface IModelPrivate {
        pub fun setBio(bio: String)
        pub fun setAddress(address: Address)
        pub fun setUri(uri: String)
    }

    pub resource NFT : IModelPrivate, IModelPublic, NonFungibleToken.INFT  {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub var uri: String?
        pub var metadata: {String: String}?
        pub let createdAt: UFix64

        access(self) var address: Address?
        access(self) var bio: String

        init(id: UInt64, name: String, nameHash: String, uri: String, bio: String, metadata: {String: String}?){
            self.id = id
            self.name = name
            self.nameHash = nameHash
            self.createdAt = getCurrentBlock().timestamp
            self.address = nil
            self.bio = bio
            self.uri = uri
            self.metadata = metadata
        }

        pub fun getBio() : String{
            return self.bio
        }
        pub fun getName(): String{
            return self.name
        }
        
        pub fun getAddress(): Address?{
            return self.address
        }

        pub fun getInfo(): ModelInfo{
            return ModelInfo(
                id: self.id,
                name: self.getName(),
                nameHash: self.nameHash,
                owner: self.address!,
                address: self.address,
                uri: self.uri,
                bio: self.bio,
                metadata: self.metadata,
                createdAt: self.createdAt
            )
        }

        pub fun setBio(bio: String){
            self.bio = bio
        }
        pub fun setAddress(address: Address){
            self.address = address
        }
        pub fun setUri(uri: String){
            self.uri = uri
        }

    }

    pub resource interface ICollectionPublic {
        pub fun borrowModel(id: UInt64): &{ModelHub.IModelPublic}
    }

    pub resource interface ICollectionPrivate {
        access(account) fun mintModel(
            name: String,
            nameHash: String,
            uri: String,
            bio: String,
            metadata: {String: String}?,
            receiver: Capability<&{NonFungibleToken.Receiver}>
        )
        pub fun borrowModelPrivate(id: UInt64): &ModelHub.NFT
    }
    
    pub resource Collection : ICollectionPrivate, ICollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic{
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init(){
            self.ownedNFTs <- {}
        }

        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT{
            let model <- self.ownedNFTs.remove(key: withdrawID) ?? panic("Model not found")
            emit Withdraw(id: withdrawID, from: self.owner?.address)
            return <- model
        }

        pub fun deposit(token: @NonFungibleToken.NFT){
            let id = token.id
            let oldModel  <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address!)
            destroy oldModel
        }

        pub fun getIDs(): [UInt64]{
            return self.ownedNFTs.keys
        }

        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }
        
        pub fun borrowModel(id: UInt64): &{ModelHub.IModelPublic} {
            pre {
                self.ownedNFTs[id] != nil : "Model does not exist"
            }

            let token = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            return token as! &ModelHub.NFT
        }
        
        // ICollectionPrivate
        access(account) fun mintModel(
            name: String,
            nameHash: String,
            uri: String,
            bio: String,
            metadata: {String: String}?,
            receiver: Capability<&{NonFungibleToken.Receiver}>
        ){
            pre {
                ModelHub.isAvailable(nameHash: nameHash) : "Model name already taken"
            }

            let model <- create ModelHub.NFT(
                                id: ModelHub.totalSupply,
                                name: name,
                                nameHash: nameHash,
                                uri: uri,
                                bio: bio,
                                metadata: metadata
                            )

            ModelHub.updateOwner(nameHash: nameHash, address: receiver.address)
            ModelHub.updateNameHashToID(nameHash: nameHash, id: model.id)
            ModelHub.totalSupply = ModelHub.totalSupply + 1

            emit ModelMinted(
                id: model.id, 
                name: name, 
                nameHash: nameHash, 
                uri: uri, 
                createdAt:  model.createdAt,
                receiver: receiver.address 
            )

            receiver.borrow()!.deposit(token: <-model)
        }

        pub fun borrowModelPrivate(id: UInt64): &ModelHub.NFT {
            pre {
                self.ownedNFTs[id] != nil: "model doesn't exist"
            }
            let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            return ref as! &ModelHub.NFT
        }

        destroy (){
            destroy self.ownedNFTs
        }
    }


    pub resource interface IRegistrarPublic {
        pub let maxNameLength: Int
        pub let prices: {String: UFix64}

        pub fun registerModel(
                name:String, 
                nameHash: String,
                uri: String,
                bio: String,
                metadata: {String: String}?,
                feeTokens: @FungibleToken.Vault, 
                receiver: Capability<&{NonFungibleToken.Receiver}>
        )
        pub fun getPrices(): {String: UFix64}
        pub fun getVaultBalance(): UFix64
    }

    pub resource Registrar: IRegistrarPublic {
        pub let maxNameLength: Int
        pub let prices: {String: UFix64}

        priv var payVault: @FungibleToken.Vault
        access(account) var modelsCollection: Capability<&ModelHub.Collection>

        init(vault: @FungibleToken.Vault, collection: Capability<&ModelHub.Collection>) {
            self.maxNameLength = 100
            self.prices = {}

            self.payVault <- vault
            self.modelsCollection = collection
        }

        pub fun registerModel(
            name:String, 
            nameHash: String,
            uri: String,
            bio: String,
            metadata: {String: String}?,
            feeTokens: @FungibleToken.Vault, 
            receiver: Capability<&{NonFungibleToken.Receiver}>
        ) {
            pre {
                name.length <= self.maxNameLength : "Model name is too long"
            }

            let nameHash = ModelHub.getModelNameHash(name: name)
            
            if ModelHub.isAvailable(nameHash: nameHash) == false {
                panic("Model name is not available")
            }

            let price = self.getPrices()[nameHash]


            if price == 0.0 || price == nil {
                panic("Price has not been set for this model")
            }

            let rentCost = price! // + service fee
            let feeSent = feeTokens.balance

            if feeSent < rentCost {
                panic("You did not send enough FLOW tokens. Expected: ".concat(rentCost.toString()))
            }

            self.payVault.deposit(from: <- feeTokens)

            self.modelsCollection.borrow()!.mintModel(name: name, nameHash: nameHash, uri: uri,bio: bio, metadata: metadata, receiver: receiver)

            // Event is emitted from mintModel ^
        }

        pub fun getPrices(): {String: UFix64} {
            return self.prices
        }

        pub fun getVaultBalance(): UFix64 {
            return self.payVault.balance
        }

        pub fun updatePayVault(vault: @FungibleToken.Vault) {
            pre {
                self.payVault.balance == 0.0 : "Withdraw balance from vault before updating"
            }

            let oldVault <- self.payVault <- vault
            destroy oldVault
        }

        pub fun withdrawVault(receiver: Capability<&{FungibleToken.Receiver}>, amount: UFix64) {
            let vault = receiver.borrow()!
            vault.deposit(from: <- self.payVault.withdraw(amount: amount))
        }

        pub fun setPrices(nameHash: String, val: UFix64) {
            self.prices[nameHash] = val
        }

        destroy() {
            destroy self.payVault
        }
    }

    // Global fun
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        let collection <- create Collection()
        return <- collection
    }

    pub fun isAvailable(nameHash: String): Bool {
        return self.owners[nameHash] == nil
    }

    pub fun getAllOwners(): {String: Address} {
        return self.owners
    }

    pub fun getAllNameHashToIDs(): {String: UInt64} {
        return self.nameHashToIDs
    }

    pub fun getModelNameHash(name: String): String {
        let forbiddenCharsUTF8 = self.forbiddenChars.utf8
        let nameUTF8 = name.utf8

        for char in forbiddenCharsUTF8 {
            if nameUTF8.contains(char) {
                panic("Illegal model name")
            }
        }

        let nameHash = String.encodeHex(HashAlgorithm.SHA3_256.hash(nameUTF8))
        return nameHash
    }

    access(account) fun updateOwner(nameHash: String, address: Address) {
        self.owners[nameHash] = address
    }

    access(account) fun updateNameHashToID(nameHash: String, id: UInt64) {
        self.nameHashToIDs[nameHash] = id
    }


}