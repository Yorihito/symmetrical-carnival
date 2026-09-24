import Foundation

/// Yamaha（YXC）の入力 ID・サウンドプログラム ID の表示名とアイコン。
/// 本体で付けた名前（getNameText）があればそちらを優先する。
/// ID の一覧: Yamaha Extended Control API Specification (Basic) 11. All ID List
enum YamahaCatalog {

    static func input(id: String, customName: String?) -> ReceiverInput {
        let (name, icon) = inputInfo(id)
        let display = (customName?.isEmpty == false) ? customName! : name
        return ReceiverInput(id: id, displayName: display, systemImage: icon)
    }

    static func soundProgram(id: String, customName: String?) -> SoundModeOption {
        let (name, icon) = programInfo(id)
        let display = (customName?.isEmpty == false) ? customName! : name
        return SoundModeOption(id: id, displayName: display, systemImage: icon)
    }

    /// ピュアダイレクトは YXC ではサウンドプログラムではなく別のスイッチ（setPureDirect）。
    /// 画面ではサウンドモードの 1 つとして並べる
    static let pureDirectID = "pure_direct"
    static let pureDirect = SoundModeOption(id: pureDirectID, displayName: "Pure Direct", systemImage: "waveform.path.ecg")

    // MARK: - Inputs

    private static func inputInfo(_ id: String) -> (String, String) {
        if let n = numbered(id, prefix: "hdmi") { return ("HDMI \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "av") { return ("AV \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "audio") { return ("AUDIO \(n)", "hifispeaker") }
        if let n = numbered(id, prefix: "optical") { return ("Optical \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "coaxial") { return ("Coaxial \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "digital") { return ("Digital \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "line") { return ("Line \(n)", "cable.connector") }
        if let n = numbered(id, prefix: "aux") { return ("AUX \(n)", "headphones.circle") }
        switch id {
        case "hdmi":      return ("HDMI", "cable.connector")
        case "tv":        return ("TV", "tv")
        case "bd_dvd":    return ("BD/DVD", "opticaldisc")
        case "cd", "audio_cd", "line_cd": return ("CD", "opticaldisc")
        case "phono":     return ("PHONO", "record.circle")
        case "tuner":     return ("Tuner", "antenna.radiowaves.left.and.right")
        case "multi_ch":  return ("Multi CH", "hifispeaker")
        case "v_aux":     return ("V-AUX", "headphones.circle")
        case "aux":       return ("AUX", "headphones.circle")
        case "audio":     return ("AUDIO", "hifispeaker")
        case "optical":   return ("Optical", "cable.connector")
        case "coaxial":   return ("Coaxial", "cable.connector")
        case "digital":   return ("Digital", "cable.connector")
        case "analog":    return ("Analog", "cable.connector")
        case "usb_dac":   return ("USB DAC", "cable.connector")
        case "usb":       return ("USB", "externaldrive")
        case "bluetooth": return ("Bluetooth", "dot.radiowaves.left.and.right")
        case "server":    return ("Server", "server.rack")
        case "net_radio": return ("Net Radio", "radio")
        case "airplay":   return ("AirPlay", "airplayaudio")
        case "spotify":   return ("Spotify", "music.note")
        case "pandora":   return ("Pandora", "music.note")
        case "siriusxm":  return ("SiriusXM", "music.note")
        case "napster", "rhapsody": return ("Napster", "music.note")
        case "juke":      return ("JUKE", "music.note")
        case "qobuz":     return ("Qobuz", "music.note")
        case "radiko":    return ("radiko", "radio")
        case "tidal":     return ("TIDAL", "music.note")
        case "deezer":    return ("Deezer", "music.note")
        case "amazon_music": return ("Amazon Music", "music.note")
        case "alexa":     return ("Alexa", "music.note")
        case "mc_link":   return ("MusicCast Link", "link")
        case "main_sync": return ("Main Zone Sync", "arrow.triangle.2.circlepath")
        default:          return (prettified(id), "square.grid.2x2")
        }
    }

    // MARK: - Sound programs

    private static func programInfo(_ id: String) -> (String, String) {
        switch id {
        case "munich", "munich_a", "munich_b": return ("Hall in Munich", "building.columns")
        case "frankfurt":        return ("Hall in Frankfurt", "building.columns")
        case "stuttgart":        return ("Hall in Stuttgart", "building.columns")
        case "vienna":           return ("Hall in Vienna", "building.columns")
        case "amsterdam":        return ("Hall in Amsterdam", "building.columns")
        case "usa_a", "usa_b":   return ("Hall in USA", "building.columns")
        case "tokyo":            return ("Hall in Tokyo", "building.columns")
        case "freiburg":         return ("Church in Freiburg", "building.columns")
        case "royaumont":        return ("Church in Royaumont", "building.columns")
        case "chamber":          return ("Chamber", "building.columns")
        case "concert":          return ("Concert", "music.mic")
        case "village_gate":     return ("Village Gate", "music.mic")
        case "village_vanguard": return ("Village Vanguard", "music.mic")
        case "warehouse_loft":   return ("Warehouse Loft", "music.mic")
        case "cellar_club":      return ("Cellar Club", "music.mic")
        case "jazz_club":        return ("Jazz Club", "music.mic")
        case "roxy_theatre":     return ("The Roxy Theatre", "music.mic")
        case "bottom_line":      return ("The Bottom Line", "music.mic")
        case "arena":            return ("Arena", "music.mic")
        case "sports":           return ("Sports", "sportscourt")
        case "action_game":      return ("Action Game", "gamecontroller")
        case "roleplaying_game": return ("Roleplaying Game", "gamecontroller")
        case "game":             return ("Game", "gamecontroller")
        case "music_video":      return ("Music Video", "music.note")
        case "music":            return ("Music", "music.note")
        case "recital_opera":    return ("Recital/Opera", "music.mic")
        case "pavilion":         return ("Pavilion", "music.mic")
        case "disco":            return ("Disco", "music.note")
        case "standard":         return ("Standard", "film")
        case "spectacle":        return ("Spectacle", "film")
        case "sci-fi":           return ("Sci-Fi", "film")
        case "adventure":        return ("Adventure", "film")
        case "drama":            return ("Drama", "film")
        case "talk_show":        return ("Talk Show", "tv")
        case "tv_program":       return ("TV Program", "tv")
        case "mono_movie":       return ("Mono Movie", "film")
        case "movie":            return ("Movie", "film")
        case "enhanced":         return ("Enhanced", "sparkles")
        case "2ch_stereo":       return ("2ch Stereo", "speaker.2")
        case "5ch_stereo":       return ("5ch Stereo", "speaker.2")
        case "7ch_stereo":       return ("7ch Stereo", "speaker.2")
        case "9ch_stereo":       return ("9ch Stereo", "speaker.2")
        case "11ch_stereo":      return ("11ch Stereo", "speaker.2")
        case "all_ch_stereo":    return ("All-Ch Stereo", "speaker.2")
        case "stereo":           return ("Stereo", "speaker.2")
        case "surr_decoder":     return ("Surround Decoder", "hifispeaker")
        case "my_surround":      return ("My Surround", "hifispeaker")
        case "target":           return ("Target", "scope")
        case "straight":         return ("Straight", "arrow.right.circle")
        case "off":              return ("Off", "circle.slash")
        case pureDirectID:       return ("Pure Direct", "waveform.path.ecg")
        default:                 return (prettified(id), "waveform")
        }
    }

    // MARK: - Helpers

    /// "hdmi3" → 3。prefix の後ろが数字だけのときに限る
    private static func numbered(_ id: String, prefix: String) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }

    /// 表示名を知らない ID を読める形にする（"net_radio" → "Net Radio"）
    private static func prettified(_ id: String) -> String {
        id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
