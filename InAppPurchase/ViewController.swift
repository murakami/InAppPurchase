//
//  ViewController.swift
//  InAppPurchase
//
//  Created by 村上幸雄 on 2021/11/29.
//

import UIKit
import StoreKit

typealias Transaction = StoreKit.Transaction

public enum StoreError: Error {
    case failedVerification
}

class ViewController: UIViewController {
    // MARK: - Properties
    
    @IBOutlet weak var requestProductsButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var debugMessage: UITextView!
    var updateListenerTask: Task<Void, Error>? = nil
    var storeProducts = [Product]()
    
    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        updateListenerTask = listenForTransactions()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        updateListenerTask?.cancel()
        
        super.viewWillDisappear(animated)
    }
        
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                await self.appendDebugMessage(text: "処理待ちのトランザクションがあった")
                do {
                    let transaction = try await self.checkVerified(result)
                    await transaction.finish()
                    await self.appendDebugMessage(text: "処理待ちの購入完了")
                } catch {
                    await self.appendDebugMessage(text: "Transaction failed verification")
                }
            }
        }
    }
    
    @IBAction func requestProductsAction() {
        Task {
            await requestProducts()
        }
    }

    func requestProducts() async {
        do {
            /* 商品情報取得 */
            self.storeProducts = try await Product.products(for: [
                "jp.co.bitz.Example.Consumable01", "jp.co.bitz.Example.Consumable02",
                "jp.co.bitz.Example.NonConsumable01", "jp.co.bitz.Example.NonConsumable02",
                "jp.co.bitz.Example.AutoRenewableSubscription01", "jp.co.bitz.Example.AutoRenewableSubscription02"
            ])
            for product in storeProducts {
                appendDebugMessage(text: product.id + " " + product.type.rawValue + " " + product.displayPrice)
            }
            tableView.reloadData()
        } catch {
            appendDebugMessage(text: "Failed product request: \(error)")
        }
    }
        
    func purchase(_ product: Product) async throws -> Transaction? {
        if self.storeProducts.isEmpty { return nil }
        do {
            /* 商品購入 */
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                appendDebugMessage(text: "購入完了")
                return transaction
            case .userCancelled, .pending:
                return nil
            default:
                return nil
            }
        } catch {
            appendDebugMessage(text: "Failed product purchase: \(error)")
            return nil
        }
    }
        
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            appendDebugMessage(text: "レシート検証に失敗")
            throw StoreError.failedVerification
        case .verified(let safe):
            appendDebugMessage(text: "レシート検証に成功")
            return safe
        }
    }

    func appendDebugMessage(text: String) {
        print(text)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.debugMessage.isSelectable = false
            self.debugMessage.text.append("\n" + text)
            self.debugMessage.selectedRange = NSRange(location: self.debugMessage.text.count, length: 0)
            self.debugMessage.isSelectable = true
            let scrollY = self.debugMessage.contentSize.height - self.debugMessage.bounds.height
            let scrollPoint = CGPoint(x: 0, y: scrollY > 0 ? scrollY : 0)
            self.debugMessage.setContentOffset(scrollPoint, animated: true)
        }
    }
}

// MARK: - UITableViewDataSource

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.storeProducts.count
    }
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "ProductCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ProductCell")
        cell.textLabel!.text = self.storeProducts[indexPath.row].displayName
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell: UITableViewCell = self.tableView(tableView, cellForRowAt: indexPath)
        for product in storeProducts {
            if cell.textLabel?.text == product.displayName {
                print("\(product.displayName)")
                Task {
                    do {
                        if try await purchase(product) != nil {
                            appendDebugMessage(text: "Success")
                        }
                    } catch StoreError.failedVerification {
                        appendDebugMessage(text: "Your purchase could not be verified by the App Store.")
                    } catch {
                        appendDebugMessage(text: "Failed product purchase: \(error)")
                    }
                }
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
