#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <fstream>
#include <string>
#include <vector>
#include <array>
#include <regex>
#include <iostream>


const std::array<std::string, 9> i2state {
    "Closed",
    "CookieWait",
    "CookieEchoed",
    "Established",
    "ShutdownReceived",
    "ShutdownAckSent",
    "ShutdownSent",
    "ShutdownPending",
    "MaxRetransmitCookie"
};
const std::array<std::string, 11> i2peermsg {
    "INIT",
    "INIT_ACK",
    "COOKIE_ECHO",
    "COOKIE_ACK",
    "COOKIE_ERROR",
    "ABORT",
    "SHUTDOWN",
    "SHUTDOWN_ACK",
    "SHUTDOWN_COMPLETE",
    "DATA",
    "DATA_ACK"
};
const std::array<std::string, 3> i2usermsg {
    "Associate",
    "Shutdown",
    "Abort"
};


struct Process {
    int pid;
    std::vector<int> states;
};



// result[0] = 0 -> Peer state
// result[0] = 1 -> Peer msg
// result[0] = 2 -> User msg
// TODO: refactor
std::array<int, 4> parse_line(std::string str) {
    std::array<int, 4> result;
    std::regex line_regex;
    std::sregex_iterator begin_it, end_it;
    

    result = {-1, -1, -1, -1};

    // Peer state
    line_regex = "[0-9]+:\tproc  ([0-9]+) \\(Peer:([0-9]+)\\).+\\[state\\[id\\] = ([0-9]+)\\]";
    begin_it = std::sregex_iterator(str.begin(), str.end(), line_regex);
    end_it = std::sregex_iterator();
    if(std::distance(begin_it, end_it) > 0) {
        result[0] = 0;
        for (std::sregex_iterator it = begin_it; it != end_it; ++it) {
            std::smatch match = *it;
            for(size_t i = 0; i < 3; i++)
                result[i + 1] = std::stoi(match[i + 1]);
        }
        return result;
    }

    // Peer msg
    line_regex = "[0-9]+:\tproc  ([0-9]+) \\(Peer:([0-9]+)\\).+\\[ToPeer!([0-9]+),[0-9],[0-9]\\]";
    begin_it = std::sregex_iterator(str.begin(), str.end(), line_regex);
    end_it = std::sregex_iterator();
    if(std::distance(begin_it, end_it) > 0) {
        result[0] = 1;
        for (std::sregex_iterator it = begin_it; it != end_it; ++it) {
            std::smatch match = *it;
            for(size_t i = 1; i < 4; i++)
                result[i] = std::stoi(match[i]);
        }
        return result;
    }

    // User msg
    line_regex = "[0-9]+:\tproc  ([0-9]+) \\(User:([0-9]+)\\).+\\[ToPeer!([0-9]+)\\]";
    begin_it = std::sregex_iterator(str.begin(), str.end(), line_regex);
    end_it = std::sregex_iterator();
    if(std::distance(begin_it, end_it) > 0) {
        result[0] = 2;
        for (std::sregex_iterator it = begin_it; it != end_it; ++it) {
            std::smatch match = *it;
            for(size_t i = 1; i < 4; i++)
                result[i] = std::stoi(match[i]);
        }
        return result;
    }

    return result;
}

int main(int argc, char** argv) {
    std::ifstream file(argv[1]);
    std::string str;
    std::array<int, 4> line_parsed;

    std::printf("participant User A\n");
    std::printf("participant Peer A\n");
    std::printf("participant Peer B\n");
    std::printf("participant User B\n");
    while(std::getline(file, str)) {
        line_parsed = parse_line(str);
        if(line_parsed[0] == -1)
            continue;
        if(line_parsed[0] == 0) {
            if(line_parsed[1] == 1)
                std::printf("box over Peer A:%s\n", i2state[line_parsed[3]].c_str());
            else if(line_parsed[1] == 2)
                std::printf("box over Peer B:%s\n", i2state[line_parsed[3]].c_str());
        }
        if(line_parsed[0] == 1) {
            if(line_parsed[1] == 1)
                std::printf("Peer A->Peer B:%s\n", i2peermsg[i2peermsg.size() - 1 - (line_parsed[3] - 1)].c_str());
            else if(line_parsed[1] == 2)
                std::printf("Peer B->Peer A:%s\n", i2peermsg[i2peermsg.size() - 1 - (line_parsed[3] - 1)].c_str());
        }
        if(line_parsed[0] == 2) {
            if(line_parsed[1] == 3)
                std::printf("User A->Peer A:%s\n", i2usermsg[i2usermsg.size() - 1 - (line_parsed[3] - 1)].c_str());
            else if(line_parsed[1] == 4)
                std::printf("User B->Peer B:%s\n", i2usermsg[i2usermsg.size() - 1 - (line_parsed[3] - 1)].c_str());
        }
    }
}
