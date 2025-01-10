import Vapor
import NIOConcurrencyHelpers
import NIOSSL

public func configure(_ app: Application) async throws {
    app.logger.logLevel = Environment.process.LOG_LEVEL ?? .debug
    
#warning("Sort")
    var config = app.http.server.configuration
    config.hostname = "127.0.0.1"
    if app.environment == .tls {
        config.port = 8443
        try config.tlsConfiguration = .makeServerConfiguration(
            certificateChain: NIOSSLCertificate.fromPEMBytes(TLSData.sampleServerCertificatePEM).map { .certificate($0) },
            privateKey: .privateKey(.init(bytes: TLSData.sampleServerPrivateKeyPEM, format: .pem))
        )
    }
    
    await app.http.server.shared.updateConfiguration(config)
    
    // routes
    try routes(app)
}

actor MemoryCache {
    var storage: [String: String] = [:]

    func get(_ key: String) -> String? { self.storage[key] }
    func set(_ key: String, to value: String?) { self.storage[key] = value }
}

extension Environment {
    static var tls: Environment { .custom(name: "tls") }
}

enum TLSData {
    static var sampleServerCertificatePEM: [UInt8] { .init("""
        -----BEGIN CERTIFICATE-----
        MIIDeTCCAmGgAwIBAgIUMJzqelT95d/JU2Yp4/XHuqhJTs4wDQYJKoZIhvcNAQEL\nBQAwTDELMAkGA1UEBhMCVVMxKTAnBgNVBAoMIFZhcG9yIERldmVsb3BtZW50IEV4
        YW1wbGUgU2VydmVyMRIwEAYDVQQDDAlsb2NhbGhvc3QwHhcNMjMwMzEwMTIyNjQw\nWhcNMjcwMzEwMTIyNjQwWjBMMQswCQYDVQQGEwJVUzEpMCcGA1UECgwgVmFwb3Ig
        RGV2ZWxvcG1lbnQgRXhhbXBsZSBTZXJ2ZXIxEjAQBgNVBAMMCWxvY2FsaG9zdDCC\nASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALavC7FuHyTwEbYUEtUDHPdE
        LCglZGypp1+qE1XuhQ1qPgx7FMBKXAYYLjSyEfK1GaorBXfLGW5xNHfSrJYVmhm2\nUOGPJbZvFtXZeufQz8B31u6sfXEJNWbJ6K8HUZkPyNRJROS5IBhDRiKxUTJOT+Ph
        pT1ZooRNd/9/v/0JoM4HEXE4oO7KIb4fM4IuVIfTdib42aMH7jKMVfVr7N2zOFnm\nMd0fmc5y0Gx/tvr13EN92lGlS3V4+YTWr7KsueQYvplJiDJ0E3AipLXRYtarsJqD
        nWhktpvbknbf9LntKJo9yL+O6CRifS8zBn/cqfFo7vuIRQyhd2q/ndjiqQoOqx8C\nAwEAAaNTMFEwHQYDVR0OBBYEFDNaYh5eewiz63D/z4Imzmd3Ey+kMB8GA1UdIwQY
        MBaAFDNaYh5eewiz63D/z4Imzmd3Ey+kMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZI\nhvcNAQELBQADggEBAEOxFji5Jlx3LdTjVG3cy5PnZWFGrREw4JE6vl258upGTEaz
        m/TQOBiSWxEG5SfMSFjaNzoHu5BU+uTUyr/gCUseFoseA+C+wsCikfSPKpmfLEW0\nNF49c6fPYWCu39wMpNCgrcXgde29V3Sar5WfYclFnQUEHqSRL22Yq+JNPnokFrja
        L9jOe/0MbZ34Gurjj9LMlVDg3p8FTKJJ9qipPMVBPy+/8ABm4qu7vx0Kacuskgc8\nu8RErJ0sqir7ggBGqgRp+Z+DC5UcqlMUZZQPKSLpCqfdrOIcDrTK9u/PU9cGdALh
        C+4n5ZIHWu66eCvARnqbCTwcOwGMxkKX/4FpI54=
        -----END CERTIFICATE-----
        """.utf8)
    }
    static var sampleServerPrivateKeyPEM: [UInt8] { .init("""
        -----BEGIN PRIVATE KEY-----
        MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQC2rwuxbh8k8BG2\nFBLVAxz3RCwoJWRsqadfqhNV7oUNaj4MexTASlwGGC40shHytRmqKwV3yxlucTR3
        0qyWFZoZtlDhjyW2bxbV2Xrn0M/Ad9burH1xCTVmyeivB1GZD8jUSUTkuSAYQ0Yi\nsVEyTk/j4aU9WaKETXf/f7/9CaDOBxFxOKDuyiG+HzOCLlSH03Ym+NmjB+4yjFX1
        a+zdszhZ5jHdH5nOctBsf7b69dxDfdpRpUt1ePmE1q+yrLnkGL6ZSYgydBNwIqS1\n0WLWq7Cag51oZLab25J23/S57SiaPci/jugkYn0vMwZ/3KnxaO77iEUMoXdqv53Y
        4qkKDqsfAgMBAAECggEANfp17YjY2fy3dwHqaJdhZSx3Eauuxy6/3lPuH6t5E/Qq\n/lwVzxWJqGFXsclV5U2eljndBT71Nj1r3+XXigc6/9Lvhh5aadPcPvbiSoHYCQo/
        70j3TcGHTmZlguYaNaxEznkRyrVqptCl9hVHpSIfl/lx7jVAgHA1f0CblWRVZ9qM\nhX42ye0xxamUdfcUFYvZ4n7Tz5G36HP+cOKlrN6nGfhmOf3hb3ILuPymCJdECvFM
        xsCXpHA2r4biYMRwkWO2+X5Scx7nVrQYizJG1iTdZnY6g1heRhzUDTcf7yjyr2++\nd+9VRI0KW5gO7q0sIarHgy7ItAAWgjGhGBASU4rebQKBgQC5xeE47WUzA1zQoDof
        u55tSp32hHKkw2ysdIO3LUSVHS/VhMMNHTo0fqhvgY7Wd25M9OBVmWbTvnSNmcU+\niVdVcd9rmD+jPEBftwjRKtXkQgJpMNuDszOQ3bJYqAUkRfT7ceuiil3H4Awdq6UE
        qvynmn7MYZN7CxcefvOQlSdpKwKBgQD7vjXAOJn7ZyGRsb1lKxNCHL9GvZthsM1h\nvyH8uvUm94Ztw5g9ON2qgPZQIwZxEY+LxnjfqaooKHE38rNdKYHMLsfgNQ2tdopR
        2sEqVL0aQP25YAYiL4jI7hGI7GwgiSiywvmhGWjU5ZIu8fKqc+8pZy4vW/EgVctQ\nuLntBvgj3QKBgGaSLEV7RcoBzEhgf1cwB0w+y7Ll9EqmoCUj++mys9BFGjkhIXTn
        M1DysdtHRG+D58HT3t1EYrL80GuygGaD/FVwFzTYDiL5zG1MqTCcHxb1n1EnKbyw\nwAL3dVZgBt69RYNjpf/Lt/X47ZegQu+t3OxJcEM2iPCB8hTjcWXeBLGbAoGAEjcT
        IJN34M73iNk5gQZ64D/AP1gc1Ba85aO0y9qjPmyOl4adj2B7+YhXSjkekDPbFRwJ\nRvW50CoM9yVigQ0tzR5dbAWqtbBsFbwkWfHDtRCayzz9dJ/H3/IJ5sRkln4WKckd
        0uBJy43I5AixrE+zMGW828RlUBelHHQhT9s/PSkCgYA6kQyV5FLBLrmnV5B8bdiU\ndEF7H/YHrRMvzH3bwfgaw7CxjUcreQ2LX84fkUFtZXzR2VS5bdZKGFDmSX0QVGPq
        zmVLrxbf0kgQjEEaSHsdIutYblHJg3bSjKoyOC20TB34sps7hpBRq6joJwjWH/rz\n6XoqNBpphe8vTBZn/FSkog==
        -----END PRIVATE KEY-----
        """.utf8)
    }
}
