//
//  Utils.swift
//  phone-test
//
//  Created by Julien Roncaglia on 15/06/2019.
//  Copyright © 2019 Julien Roncaglia. All rights reserved.
//

import Foundation

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + self.lowercased().dropFirst()
    }
}
