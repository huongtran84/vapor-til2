/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Vapor
import Leaf
import Fluent
import Authentication
struct WebsiteController: RouteCollection {
    func boot(router: Router) throws {
        let authSessionRoutes = router.grouped(User.authSessionsMiddleware())
        authSessionRoutes.get(use: indexHandler)
        authSessionRoutes.get("acronyms", Acronym.parameter, use: acronymHandler)
        authSessionRoutes.get("users",User.parameter, use: userHandler)
        authSessionRoutes.get("users", use: allUsersHandler)
        authSessionRoutes.get("categories", use: allCategoriesHandler)
        authSessionRoutes.get("categories",Category.parameter,use:categoryHandler)
        authSessionRoutes.get("login", use: loginHandler)
        authSessionRoutes.post("logout", use: logoutHandler)
        authSessionRoutes.post(LoginPostData.self, at: "login", use: loginPostHandler)
        let authProtectedRoutes = authSessionRoutes.grouped(RedirectMiddleware<User>(path: "/login"))
        authSessionRoutes.get("register", use: registerHandler)
        authSessionRoutes.post(RegisterData.self, at: "register", use: registerPostHandler)
        
        authProtectedRoutes.get("acronyms","create", use: createAcronymHandler)
        authProtectedRoutes.post(CreateAcronymData.self, at: "acronyms","create", use: createAcronymPostHandler)
        authProtectedRoutes.get("acronyms",Acronym.parameter,"edit", use: editAcronymHandler)
        authProtectedRoutes.post("acronyms",Acronym.parameter,"edit", use: editAcronymPostHandler)
        authProtectedRoutes.post("acronyms",Acronym.parameter,"delete", use: deleteAcronymHandler)
        
        
        
        
    }
    
    func indexHandler(_ req: Request) throws -> Future<View> {
        return Acronym.query(on: req)
            .all()
            .flatMap(to: View.self) { acronyms in
                let acronymsData = acronyms.isEmpty ? nil : acronyms
                let isLoggedIn = try req.isAuthenticated(User.self)
                let showCookiesMessage =  req.http.cookies["cookies-accepted"] == nil
                let context = IndexContext(title: "Homepage",
                                           acronyms: acronymsData,userLoggedIn:isLoggedIn,showCookieMessage:showCookiesMessage)
                return try req.view().render("index", context)
        }
    }
    
    func acronymHandler(_ req: Request) throws -> Future<View> {
        return try req.parameters.next(Acronym.self)
            .flatMap(to: View.self) { acronym in
                return acronym.user
                    .get(on: req)
                    .flatMap(to: View.self) { user in
                        let categories = try acronym.categories.query(on: req).all()
                        let context = AcronymContext(title: acronym.short,
                                                     acronym: acronym,
                                                     user: user,categories:categories)
                        return try req.view().render("acronyms", context)
                }
        }
    }
    func userHandler(_ req: Request) throws -> Future<View> {
        return try req.parameters.next(User.self).flatMap(to: View.self, { user in
            return try user.acronyms.query(on: req).all().flatMap(to: View.self, { acronyms in
                let context = UserContext(title: user.name, acronyms: acronyms, user: user)
                return try req.view().render("user", context)
            })
        })
    }
    func allUsersHandler(_ req: Request) throws -> Future<View> {
        return User.query(on: req).all().flatMap(to: View.self, { users in
            let usersAllContext = AllUsersContext(title: "All Users", users: users)
            return try req.view().render("allUsers", usersAllContext)
        })
    }
    func allCategoriesHandler(_ req: Request) throws -> Future<View> {
        let categories = Category.query(on: req).all()
        let context = AllCategoriesContext(categories: categories)
        return try req.view().render("allCategories", context)
    }
    
    func categoryHandler(_ req: Request) throws -> Future<View> {
        return try req.parameters.next(Category.self)
            .flatMap(to: View.self) { category in
                let acronyms = try category.acronyms.query(on: req).all()
                let context = CategoryContext(title: category.name,
                                              category: category,
                                              acronyms: acronyms)
                return try req.view().render("category", context)
        }
    }
    func createAcronymHandler(_ req: Request) throws -> Future<View> {
        let token = try CryptoRandom().generateData(count: 16).base64EncodedString()
        let context = CreateAcronymContext(csrfToken: token)
        try req.session()["CSRF_TOKEN"] = token
        return try req.view().render("createAcronym", context)
    }
    func createAcronymPostHandler(_ req:Request,data:CreateAcronymData) throws -> Future<Response> {
        let expectedToken = try req.session()["CSRF_TOKEN"]
        // 2
        try req.session()["CSRF_TOKEN"] = nil
        // 3
        guard expectedToken == data.csrfToken else {
            throw Abort(.badRequest)
        }
        let user = try req.requireAuthenticated(User.self)
        let acronym = try Acronym(short: data.short, long: data.long, userID: user.requireID())
        return acronym.save(on: req).flatMap(to: Response.self, { acronym in
            guard let id = acronym.id else {
                throw Abort(.internalServerError)
            }
            var categorySave : [Future<Void>] = []
            for category in data.categories ?? [] {
                try categorySave.append(Category.addCategory(category, to: acronym, on: req))
            }
            let redirect = req.redirect(to: "/acronyms/\(id)")
            return categorySave.flatten(on: req).transform(to: redirect)
        })
    }
    func editAcronymHandler(_ req : Request) throws -> Future<View> {
        
        return try req.parameters.next(Acronym.self).flatMap(to: View.self, { acronym in
            let categories = try acronym.categories.query(on: req).all();
            let editAcronymContext = EditAcronymContext(acronym: acronym, categories: categories)
            return try req.view().render("createAcronym", editAcronymContext)
        })
    }
    func editAcronymPostHandler(_ req: Request) throws -> Future<Response> {
        return try flatMap(to: Response.self, req.parameters.next(Acronym.self), req.content.decode(CreateAcronymData.self), { acronym,data in
            let user = try req.requireAuthenticated(User.self)
            acronym.short = data.short
            acronym.long = data.long
            acronym.userID = try user.requireID()
            return acronym.save(on: req).flatMap(to: Response.self, { savedAcronym in
                guard let id = savedAcronym.id else {
                    throw Abort(.internalServerError)
                }
                return try acronym.categories.query(on: req).all().flatMap(to: Response.self, { existCategories in
                    let existStringArray = existCategories.map{$0.name}
                    let existingSet = Set<String>(existStringArray)
                    let newSet = Set<String>(data.categories ?? [])
                    let categoriesToAdd = newSet.subtracting(existingSet)
                    let categoriesToRemove = existingSet.subtracting(newSet)
                    var categoryResults: [Future<Void>] = []
                    // 8
                    for newCategory in categoriesToAdd {
                        categoryResults.append(
                            try Category.addCategory(
                                newCategory,
                                to: acronym,
                                on: req))
                    }
                    
                    for categoryNameToRemove in categoriesToRemove {
                        // 10
                        let categoryToRemove = existCategories.first {
                            $0.name == categoryNameToRemove
                        }
                        // 11
                        if let category = categoryToRemove {
                            categoryResults.append(
                                acronym.categories.detach(category, on: req))
                        }
                    }
                    
                    return categoryResults.flatten(on: req).transform(to: req.redirect(to: "/acronyms/\(id)"))
                    
                    
                    
                    
                })
            })
        })
    }
    func logoutHandler(_ req : Request) throws -> Response {
        try req.unauthenticate(User.self)
        return req.redirect(to: "/")
    }
    func registerHandler(_ req: Request) throws -> Future<View> {
        let context : RegisterContext
        if let message = req.query[String.self,at:"message"] {
            context = RegisterContext(message: message)
        } else {
            context = RegisterContext()
        }
        return try req.view().render("register", context)
    }
    func registerPostHandler(_ req:Request,data:RegisterData) throws -> Future<Response> {
        do {
            try data.validate()
        } catch(let error) {
            let redirect:String
            if let error = error as? ValidationError,let message = error.reason.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed){
                redirect = "/register?message=\(message)"
            } else {
                redirect = "/register?message=Unknow+error"
            }
            return req.future(req.redirect(to: redirect))
        }
        
        let password = try BCrypt.hash(data.password)
        var twitterURL: String?
        if let twitter = data.twitterURL,!twitter.isEmpty {
            twitterURL = twitter
        }
        let user = User(name: data.name, username: data.username, password: password,twitterURL:twitterURL)
        return  user.save(on: req).map(to: Response.self, { user in
            try req.authenticateSession(user)
            return req.redirect(to: "/")
        })
    }
    func deleteAcronymHandler(_ req: Request) throws ->Future<Response> {
        return try req.parameters.next(Acronym.self).delete(on: req).transform(to: req.redirect(to: "/"))
    }
    func loginHandler(_ req: Request) throws -> Future<View> {
        let context:LoginContext
        if req.query[Bool.self,at : "error"] != nil {
            context = LoginContext(loginError: true)
        } else {
            context = LoginContext()
        }
        return try req.view().render("login", context)
    }
    func loginPostHandler(_ request: Request,postData:LoginPostData) throws -> Future<Response> {
        return User.authenticate(username: postData.username, password: postData.password, using: BCryptDigest(), on: request).map(to: Response.self){
            user in
            guard let user = user else {
                return request.redirect(to: "/login?error")
            }
            try request.authenticateSession(user)
            return request.redirect(to: "/")
        }
    }
}

struct IndexContext: Encodable {
    let title: String
    let acronyms: [Acronym]?
    let userLoggedIn: Bool
    let showCookieMessage: Bool
}

struct AcronymContext: Encodable {
    let title: String
    let acronym: Acronym
    let user: User
    let categories: Future<[Category]>
}
struct UserContext : Encodable {
    let title: String
    let acronyms: [Acronym]
    let user: User
}
struct AllUsersContext : Encodable {
    let title: String
    let users: [User]
}
struct AllCategoriesContext: Encodable {
    let title = "All Categories"
    let categories: Future<[Category]>
}

struct CategoryContext: Encodable {
    let title: String
    let category: Category
    let acronyms: Future<[Acronym]>
}
struct CreateAcronymContext: Encodable {
    let title = "Create An Acronym"
    let csrfToken: String
}
struct EditAcronymContext : Encodable {
    let title = "Edit Acronym"
    let acronym:Acronym
    let editing = true
    let categories : Future<[Category]>
}
struct CreateAcronymData: Content {
    let short: String
    let long: String
    let categories: [String]?
    let csrfToken: String
    
}

struct LoginContext : Encodable {
    let title = "Log In"
    let loginError : Bool
    init(loginError:Bool = false) {
        self.loginError = loginError
    }
    
}
struct LoginPostData : Content {
    let username: String
    let  password : String
    
}
struct RegisterContext : Encodable {
    let title = "Register"
    let message : String?
    init(message:String? = nil) {
        self.message = message
    }
}
struct RegisterData : Content {
    let name : String
    let username: String
    let password : String
    let confirmPassword: String
    let twitterURL: String?
    
}
extension RegisterData : Reflectable,Validatable {
    static func validations() throws -> Validations<RegisterData> {
        var validations = Validations(RegisterData.self)
        try validations.add(\.name, .ascii)
        try validations.add(\.username, .alphanumeric && .count(3...))
        try validations.add(\.password, .count(8...))
        validations.add("password match") { (model) in
            guard model.confirmPassword == model.password else {
                throw BasicValidationError("password not match")
            }
        }
        return validations
    }
}

