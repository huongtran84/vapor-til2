import Vapor
import FluentPostgreSQL

struct AddTwitterURLToUser : Migration {
    static func revert(on conn: PostgreSQLConnection) -> Future<Void> {
        return Database.update(User.self, on: conn, closure: { builder in
            builder.deleteField(for: \.twitterURL)
        })
    }
    
    
    typealias Database  = PostgreSQLDatabase
    static func prepare(on conn: PostgreSQLConnection) -> Future<Void> {
       return Database.update(User.self, on: conn) { builder in
            builder.field(for: \.twitterURL)
        }
    }
}
