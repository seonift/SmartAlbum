//
//  PhotoLibrary.swift
//  SmartAlbum
//
//  Created by 진형탁 on 2017. 11. 20..
//  Copyright © 2017년 team-b. All rights reserved.
//

import Foundation
import Photos
import RealmSwift
import MapKit

enum ViewMode {
    case thumbnail
    case full
}

extension PHAsset {
    
    func getURL(completionHandler : @escaping ((_ responseURL : URL?) -> Void)) {
        if self.mediaType == .image {
            let options: PHContentEditingInputRequestOptions = PHContentEditingInputRequestOptions()
            options.canHandleAdjustmentData = {(adjustmeta: PHAdjustmentData) -> Bool in
                return true
            }
            self.requestContentEditingInput(with: options, completionHandler: {(contentEditingInput: PHContentEditingInput?, _: [AnyHashable : Any]) -> Void in
                completionHandler(contentEditingInput!.fullSizeImageURL as URL?)
            })
        } else if self.mediaType == .video {
            let options: PHVideoRequestOptions = PHVideoRequestOptions()
            options.version = .original
            PHImageManager.default().requestAVAsset(forVideo: self, options: options, resultHandler: {(asset: AVAsset?, _: AVAudioMix?, _: [AnyHashable : Any]?) -> Void in
                if let urlAsset = asset as? AVURLAsset {
                    let localVideoUrl: URL = urlAsset.url as URL
                    completionHandler(localVideoUrl)
                } else {
                    completionHandler(nil)
                }
            })
        }
    }
}

class PhotoLibrary {
    fileprivate var imgManager: PHImageManager
    fileprivate var requestOptions: PHImageRequestOptions
    fileprivate var fetchOptions: PHFetchOptions
    fileprivate var fetchResult: PHFetchResult<PHAsset>
    let analysisController = AnalysisController()
    let formatter = DateFormatter()
    let locationService = LocationServices()
    
    init () {
        imgManager = PHImageManager.default()
        requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                             PHAssetMediaType.image.rawValue,
                                             PHAssetMediaType.video.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending: false)]
        fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        formatter.dateFormat = "yyyy.MM"
    }

    var count: Int {
        return fetchResult.count
    }
    
    // MARK: - Function
    
    func getAsset(at index: Int) -> PHAsset? {
        guard index < fetchResult.count else { return nil }
        return fetchResult.object(at: index) as PHAsset
    }
    
    func checkPhotoAnalysis(url: String) -> Bool {
        let realm = try! Realm()
        let isChecked = (realm.objects(AnalysisAsset.self).filter("url = %@", url).count > 0)
        
        return isChecked
    }
    
    func setDB() {
        
        for index in 0..<fetchResult.count {
            
            //CGSize for detect face
            imgManager.requestImage(for: fetchResult.object(at: index) as PHAsset, targetSize: CGSize(width: 200.0, height: 200.0), contentMode: PHImageContentMode.aspectFill, options: requestOptions) { (image, _) in
                
                let asset = self.fetchResult.object(at: index)
                var url = String()
                url = asset.localIdentifier
                
                // for pass DB file
                if self.checkPhotoAnalysis(url: url) {
                    return
                }
                
                var location = String()
                let isVideo = (asset.mediaType == .video)
                var creationDate = String()
                var keyword = String()
                var confidence = Double()
                
                guard let uiImage = image else {
                    fatalError("no image")
                }
                
                if let latitude = asset.location?.coordinate.latitude, let longtitude = asset.location?.coordinate.longitude {
                    self.locationService.getCity(lati: latitude, longti: longtitude) {result in
                        location = result
                    }
                }
                
                if let imageDate = asset.creationDate {
                    creationDate = self.formatter.string(from: imageDate)
                } else {
                    creationDate = "0000.00"
                }
    
                if let ciImage = CIImage(image: uiImage) {

                    self.analysisController.detectFace(image: ciImage) { result in
                        if result > 0 {
                            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "detectEmmotion"), object: nil, userInfo: ["url": url, "isVideo": isVideo, "location": location, "creationDate": creationDate, "ciImage": ciImage])
                        }
                    }
                    
                    self.analysisController.getInfo(image: ciImage) { result in
                        keyword = result.0
                        confidence = result.1

                        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "setData"), object: nil, userInfo: ["url": url, "isVideo": isVideo, "location": location, "creationDate": creationDate, "keyword": keyword, "confidence": confidence])
                    }
                }
            }
        }
    }
    
    func setLibrary(mode selectMode: ViewMode = .full, at index: Int, completion block: @escaping (UIImage?, Bool) -> ()) {
        if index < fetchResult.count {
            var size: CGSize = UIScreen.main.bounds.size
            if selectMode == .thumbnail {
                // As the size increases, there is an error that the image in the collectionview is not shown.
                size = CGSize(width: 100, height: 100)
            }
            imgManager.requestImage(for: fetchResult.object(at: index) as PHAsset, targetSize: size, contentMode: PHImageContentMode.aspectFill, options: requestOptions) { (image, _) in
                // check Photo or Video
                let asset = self.fetchResult.object(at: index)
                
                var isVideo: Bool = false
                if asset.mediaType == .video {
                    isVideo = true
                }
                block(image, isVideo)
            }
        } else {
            block(nil, false)
        }
    }
    
    func getPhoto(at index: Int) -> UIImage {
        var result = UIImage()
        imgManager.requestImage(for: fetchResult.object(at: index) as PHAsset, targetSize: UIScreen.main.bounds.size, contentMode: PHImageContentMode.aspectFill, options: requestOptions) { (image, _) in
                if let image = image {
                    result = image
            }
        }
        return result
    }
    
    func getAllPhotos() -> [UIImage] {
        var resultArray = [UIImage]()
        for index in 0..<fetchResult.count {
            imgManager.requestImage(for: fetchResult.object(at: index) as PHAsset, targetSize: UIScreen.main.bounds.size, contentMode: PHImageContentMode.aspectFill, options: requestOptions) { (image, _) in
                
                if let image = image {
                    resultArray.append(image)
                }
            }
        }
        return resultArray
    }
    
    func convertPHAssetsToUIImages(assetArray: [PHAsset]) -> [UIImage] {
        var resultArray = [UIImage]()
        for index in 0..<assetArray.count {
            imgManager.requestImage(for: assetArray[index] as PHAsset, targetSize: UIScreen.main.bounds.size, contentMode: PHImageContentMode.aspectFill, options: requestOptions) { (image, _) in
                
                if let image = image {
                    resultArray.append(image)
                }
            }
        }
        return resultArray
    }
    
   
}
