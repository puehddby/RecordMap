//
//  SemiModalViewController.swift
//  RecordMap
//
//  Created by 杉田 尚哉 on 2019/02/04.
//  Copyright © 2019 hisayasugita. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa
import RealmSwift

final class SemiModalViewController: UIViewController {

    @IBOutlet weak private var tableView: UITableView!
    
    private let disposeBag = DisposeBag()
    var favoriteList = BehaviorRelay<Results<LocationModel>>(value: LocationModel.read())
    var refreshTrigger = PublishSubject<Void>()
    var selected = PublishSubject<Int>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
        bind()
    }
    
    func setup() {
        tableView.register(cellType: SemiModalTableViewCell.self)
    }
    
    func bind() {
        refreshTrigger.asObservable()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [unowned self] in
                self.updateTableView()
            })
            .disposed(by: disposeBag)
        
        tableView.rx.itemSelected
            .map { $0.row }
            .bind(to: selected)
            .disposed(by: disposeBag)
    }
    
    func updateTableView() {
        let list = LocationModel.read()
        favoriteList.accept(list)
        tableView.reloadData()
    }
}

extension SemiModalViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SemiModal.TableView.heightForRow
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            favoriteList.value[indexPath.row].delete()
            tableView.deleteRows(at: [indexPath], with: .fade)
        // FIXME: mapViewのAnnotationも消す
        default:
            break
        }
    }
}

extension SemiModalViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return favoriteList.value.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(for: indexPath) as SemiModalTableViewCell
        cell.configuration(data: favoriteList.value[indexPath.row])
        return cell
    }
}

extension SemiModalViewController {
    var table: UITableView {
        return tableView
    }
}
