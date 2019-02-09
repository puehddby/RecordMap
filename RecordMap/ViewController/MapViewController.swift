//
//  MapViewController.swift
//  RecordMap
//
//  Created by 杉田 尚哉 on 2019/01/31.
//  Copyright © 2019 hisayasugita. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

import RxSwift
import RxCocoa
import SnapKit
import FloatingPanel
import RealmSwift

final class MapViewController: UIViewController {

    @IBOutlet weak private var mapView: MKMapView!
    @IBOutlet weak private var dropPinButton: UIButton!
    @IBOutlet weak private var segmentedControl: UISegmentedControl!
    
    private lazy var floatingPanelController: FloatingPanelController = {preconditionFailure()}()
    private lazy var locationManager: CLLocationManager = {preconditionFailure()}()
    private lazy var promoteView: PromoteView = {preconditionFailure()}()
    private lazy var semiModalVC: SemiModalViewController = {preconditionFailure()}()
    
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0
    private var address: String = ""
    private var favoriteList: Results<LocationModel>?
    
    private let disposeBag = DisposeBag()
    let added = PublishSubject<Void>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // FIXME: スプラッシュをもっとかっこよくしたい
        // FIXME: 右上のコンパスの位置を変更したい
        
        print(segmentedControl.layer.cornerRadius)
        
        setup()
        bind()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        reloadMapView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        floatingPanelController.removePanelFromParent(animated: true)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case StoryboardSegue.Main.modalRegister.rawValue:
            let vc = segue.destination as! RegisterViewController
            vc.latitude.accept(latitude)
            vc.longitude.accept(longitude)
            vc.postDismissionAction = { self.added.onNext(()) }
            updateAddress(to: vc, latitude: latitude, longitude: longitude)
        default:
            break
        }
    }
    
    // -----------------------
    // - Private Functions
    // -----------------------
    
    func setup() {
        // - Location Manager
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest // 最高精度
        
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
            locationManager.distanceFilter = Map.distanceFilter
            locationManager.startUpdatingLocation()
        }
        
        // - Map View
        mapView.setCenter(mapView.userLocation.coordinate, animated: true)
        mapView.userTrackingMode = .follow
        mapView.showsUserLocation = true
        setRegion(coordinate: mapView.userLocation.coordinate)
        
        // - Promote View
        promoteView = PromoteView.loadFromNib()
        promoteView.isHidden = true
        view.addSubview(promoteView)
        promoteView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // - Floating Panel
        floatingPanelController = FloatingPanelController()
        floatingPanelController.surfaceView.layer.cornerRadius = 12
        floatingPanelController.surfaceView.layer.masksToBounds = true
        floatingPanelController.surfaceView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
        floatingPanelController.delegate = self
        semiModalVC = StoryboardScene.SemiModal.initialScene.instantiate()
        floatingPanelController.set(contentViewController: semiModalVC)
        floatingPanelController.track(scrollView: semiModalVC.table)
        floatingPanelController.addPanel(toParent: self, belowView: nil, animated: false)
    }
    
    func bind() {
        dropPinButton.rx.tap.asDriver()
            .drive(onNext: { [unowned self] in
                self.perform(segue: StoryboardSegue.Main.modalRegister)
            })
            .disposed(by: disposeBag)
        
        let addedLocationData = added.share(replay: 1)
        addedLocationData
            .bind(to: semiModalVC.refreshTrigger)
            .disposed(by: disposeBag)
        addedLocationData
            .subscribe(onNext: { [unowned self] in
                self.reloadMapView()
            })
            .disposed(by: disposeBag)
        
        semiModalVC.selected
            .subscribe(onNext: { [unowned self] selected in
                guard let list = self.favoriteList else { return }
                let selectedData = list[selected]
                let coordinate = CLLocationCoordinate2D(
                    latitude: selectedData.latitude,
                    longitude: selectedData.longitude
                )
                self.setRegion(coordinate: coordinate)
                self.floatingPanelController.move(to: .tip, animated: true)
                self.semiModalVC.table.deselectRow(at: [0, selected], animated: true)
                // FIXME: 選択されたセルに紐づくAnnotationを拡大したい
            })
            .disposed(by: disposeBag)
        
        semiModalVC.deleted
            .subscribe(onNext: { [unowned self] index in
                self.mapView.removeAnnotation(self.mapView.annotations[index])
                self.reloadMapView()
            })
            .disposed(by: disposeBag)
        
        segmentedControl.rx.value
            .subscribe(onNext: { [unowned self] index in
                switch index {
                case 0:
                    self.mapView.mapType = .standard
                case 1:
                    self.mapView.mapType = .satelliteFlyover
                case 2:
                    self.mapView.mapType = .hybridFlyover
                default:
                    break
                }
            })
            .disposed(by: disposeBag)
    }
    
    func reloadMapView() {
        // put pins to mapView
        // FIXME: 限定的に再描画する
        favoriteList = LocationModel.read()
        guard let favoriteList = favoriteList else { return }
        mapView.removeAnnotations(mapView.annotations)
        favoriteList.forEach { data in
            // FIXME: 新しくAnnotationを生成せずに、データからmapViewに反映したい
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: data.latitude, longitude: data.longitude)
            annotation.title = data.name
            annotation.subtitle = data.address
            mapView.addAnnotation(annotation)
        }
        debugPrint(favoriteList)
    }
    
    func setRegion(coordinate: CLLocationCoordinate2D) {
        // focus 'coordinate'
        let span = MKCoordinateSpan(
            latitudeDelta: Map.latitudeDelta,
            longitudeDelta: Map.longitudeDelta
        )
        let region = MKCoordinateRegion(center: coordinate, span: span)
        mapView.setRegion(region, animated: true)
    }
    
    func updateAddress(to vc: RegisterViewController, latitude: Double, longitude: Double) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            var address: String = ""
            address += placemark.country ?? ""
            address += placemark.administrativeArea ?? ""
            address += placemark.locality ?? ""
            address += placemark.thoroughfare ?? ""
            address += placemark.subThoroughfare ?? ""
            vc.address.accept(address)
        }
    }
}

extension MapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // called when user authorization is updated
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            promoteView.isHidden = false
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // called when user location is updated
        if let coordinate = locations.last?.coordinate {
            // follow the current location
            setRegion(coordinate: coordinate)
            
            // draw circle
            let circle = MKCircle(center: coordinate, radius: Map.circleRadius)
            mapView.addOverlay(circle)
            
            // reflect stored proparties
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }
}

extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let circleView = MKCircleRenderer(overlay: overlay)
        circleView.fillColor = .red
        circleView.alpha = 0.9
        return circleView
    }
}

extension MapViewController: FloatingPanelControllerDelegate {
    func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        let floatingPanelLayout = MapViewFloatingPanelLayout()
        return floatingPanelLayout
    }
}

class MapViewFloatingPanelLayout: FloatingPanelLayout {
    var initialPosition: FloatingPanelPosition {
        return .tip
    }
    var supportedPositions: Set<FloatingPanelPosition> {
        return [.full, .tip]
    }
    
    func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .full:
            return Map.FloatingPanel.fullPosition
        case .tip:
            return Map.FloatingPanel.tipPosition
        default:
            return nil
        }
    }
    
    func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        return [
            surfaceView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: Map.FloatingPanel.sideSpace),
            surfaceView.widthAnchor.constraint(equalToConstant: Map.FloatingPanel.width)
        ]
    }
}
